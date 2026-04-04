unit zplnet;

{$mode objfpc}{$H+}

{ Encapsulates the TCP server that receives ZPL print jobs on a configurable
  port (default 9100). The server uses a polling model: the caller must invoke
  Poll periodically (e.g. from a TTimer) so incoming connections are processed
  on the main thread without blocking the UI.

  Usage:
    FServer := TZplTcpServer.Create('0.0.0.0', 9100);
    FServer.OnDataReceived := @HandleZplData;
    // in a TTimer.OnTimer handler:
    FServer.Poll;
    // cleanup:
    FServer.Free;
}

interface

uses
  Classes, SysUtils, ssockets, lazlogger;

const
  { Maximum accepted ZPL payload in bytes. Jobs larger than this are truncated
    and a warning is written to the debug log. 1 MB is generous for any real-
    world label. }
  ZplMaxDataSize = 1048576;

type
  EZplNetError = class(Exception);

  { Event fired on the main thread after a complete ZPL job has been received.
    ZplData is positioned at 0 and owned by the server — the handler must copy
    any data it wishes to keep before returning. }
  TZplDataReceivedEvent = procedure(const ZplData: TMemoryStream) of object;

  { TZplTcpServer
    Wraps TINetServer with safe, buffered reading into a TMemoryStream. }
  TZplTcpServer = class
  private
    FServer: TINetServer;
    FOnDataReceived: TZplDataReceivedEvent;
    procedure HandleConnection(Sender: TObject; DataStream: TSocketStream);
    procedure HandleIdle(Sender: TObject);
    function GetPort: integer;
  public
    constructor Create(const BindAddress: string; Port: integer);
    destructor Destroy; override;

    { Call from a TTimer.OnTimer handler to process pending connections. }
    procedure Poll;

    { The TCP port this server is listening on. }
    property Port: integer read GetPort;

    { Fired when a complete ZPL job has been read from the socket. }
    property OnDataReceived: TZplDataReceivedEvent read FOnDataReceived write FOnDataReceived;
  end;

implementation

constructor TZplTcpServer.Create(const BindAddress: string; Port: integer);
begin
  inherited Create;
  FServer := TINetServer.Create(BindAddress, Port);
  FServer.ReuseAddress := True;
  FServer.MaxConnections := 1;
  FServer.OnConnect := @HandleConnection;
  FServer.OnIdle := @HandleIdle;
  FServer.AcceptIdleTimeOut := 100;
  FServer.Bind;
  FServer.Listen;
end;

destructor TZplTcpServer.Destroy;
begin
  FreeAndNil(FServer);
  inherited Destroy;
end;

procedure TZplTcpServer.Poll;
begin
  FServer.StartAccepting;
end;

function TZplTcpServer.GetPort: integer;
begin
  Result := FServer.Port;
end;

{ Reads all available bytes from DataStream into a TMemoryStream using a fixed-
  size chunk buffer to avoid unsafe pointer arithmetic. The stream is capped at
  ZplMaxDataSize to prevent unbounded memory growth. }
procedure TZplTcpServer.HandleConnection(Sender: TObject; DataStream: TSocketStream);
const
  ReadChunkSize = 4096;
var
  ZplData: TMemoryStream;
  Buffer: array[0..ReadChunkSize - 1] of byte;
  BytesRead: integer;
  BytesAccepted: int64;
begin
  ZplData := TMemoryStream.Create;
  try
    BytesAccepted := 0;
    repeat
      BytesRead := DataStream.Read(Buffer, SizeOf(Buffer));
      if BytesRead > 0 then
      begin
        BytesAccepted := BytesAccepted + BytesRead;
        if BytesAccepted > ZplMaxDataSize then
        begin
          DebugLn('ZplTcpServer: incoming ZPL job exceeds %d bytes; ' + 'truncating remainder', [ZplMaxDataSize]);
          Break;
        end;
        ZplData.Write(Buffer, BytesRead);
      end;
    until BytesRead <= 0;

    ZplData.Position := 0;
    if Assigned(FOnDataReceived) then
      FOnDataReceived(ZplData);
  finally
    FreeAndNil(ZplData);
    DataStream.Free;
  end;
end;

procedure TZplTcpServer.HandleIdle(Sender: TObject);
begin
  FServer.StopAccepting;
end;

end.

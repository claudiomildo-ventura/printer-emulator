unit zplrenderthread;

{$mode objfpc}{$H+}

{ Background thread for rendering ZPL labels via the Labelary API.

  Usage:
    Thread := TZplRenderThread.Create(ZplData, Settings);
    Thread.OnRenderComplete := @HandleRenderComplete;
    Thread.Start;

  The OnRenderComplete callback is fired on the MAIN thread via Synchronize,
  so the handler can safely update UI controls. }

interface

uses
  Classes, SysUtils, zplview_settings, zplprocessor;

type
  TRenderCompleteEvent = procedure(const ImageData: TMemoryStream;
    const ErrorMsg: string) of object;

  { TZplRenderThread }

  TZplRenderThread = class(TThread)
  private
    FZplData: TMemoryStream;
    FSettings: ZViewSettings;
    FImageData: TMemoryStream;
    FErrorMsg: string;
    FOnRenderComplete: TRenderCompleteEvent;
    procedure DoRenderComplete;
  protected
    procedure Execute; override;
  public
    { Creates the thread. ZplData is COPIED internally so the caller retains
      ownership of the original stream. The thread frees itself on completion. }
    constructor Create(const ZplData: TMemoryStream;
      const Settings: ZViewSettings);
    destructor Destroy; override;

    property OnRenderComplete: TRenderCompleteEvent
      read FOnRenderComplete write FOnRenderComplete;
  end;

implementation

constructor TZplRenderThread.Create(const ZplData: TMemoryStream;
  const Settings: ZViewSettings);
begin
  inherited Create(True); // create suspended
  FreeOnTerminate := True;

  FSettings := Settings;

  FZplData := TMemoryStream.Create;
  ZplData.Position := 0;
  FZplData.CopyFrom(ZplData, ZplData.Size);
  FZplData.Position := 0;

  FImageData := TMemoryStream.Create;
  FErrorMsg := '';
end;

destructor TZplRenderThread.Destroy;
begin
  FreeAndNil(FZplData);
  // FImageData ownership is transferred to the callback; nil it if not delivered
  FreeAndNil(FImageData);
  inherited Destroy;
end;

procedure TZplRenderThread.Execute;
begin
  try
    FetchLabelImage(FZplData, FSettings, FImageData);
  except
    on E: Exception do
      FErrorMsg := E.Message;
  end;

  if not Terminated then
    Synchronize(@DoRenderComplete);
end;

procedure TZplRenderThread.DoRenderComplete;
begin
  if Assigned(FOnRenderComplete) then
    FOnRenderComplete(FImageData, FErrorMsg);
end;

end.

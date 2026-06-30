unit zplview_renderer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpclient, zplview_settings;

type
  IZplRenderer = interface
    ['{3F7A1BC0-4E2D-4C8B-9F5A-D6E8C2A14B73}']
    function Render(ZplData: Pointer; ZplLen: Integer;
                    const Settings: ZViewSettings;
                    Output: TMemoryStream): Boolean;
    function GetLastError: string;
  end;

  TLabelaryRenderer = class(TInterfacedObject, IZplRenderer)
  private
    FLastError: string;
    function ResolutionToDpmm(Resolution: Integer): string;
    function BuildURL(const Settings: ZViewSettings): string;
  public
    function Render(ZplData: Pointer; ZplLen: Integer;
                    const Settings: ZViewSettings;
                    Output: TMemoryStream): Boolean;
    function GetLastError: string;
  end;

implementation

function TLabelaryRenderer.ResolutionToDpmm(Resolution: Integer): string;
begin
  case Resolution of
    152: Result := '6dpmm';
    300: Result := '12dpmm';
    600: Result := '24dpmm';
  else
    Result := '8dpmm'; // 203 DPI default
  end;
end;

function TLabelaryRenderer.BuildURL(const Settings: ZViewSettings): string;
var
  FmtSet: TFormatSettings;
begin
  FmtSet := DefaultFormatSettings;
  FmtSet.DecimalSeparator := '.';
  Result := Format('http://api.labelary.com/v1/printers/%s/labels/%nx%n/0/',
    [ResolutionToDpmm(Settings.resolution), Settings.width, Settings.height],
    FmtSet);
end;

function TLabelaryRenderer.Render(ZplData: Pointer; ZplLen: Integer;
  const Settings: ZViewSettings; Output: TMemoryStream): Boolean;
var
  Client: TFPHTTPClient;
  PostData: TMemoryStream;
  ErrorMsg: string;
begin
  Result := False;
  FLastError := '';
  Client := TFPHTTPClient.Create(nil);
  PostData := TMemoryStream.Create;
  try
    Client.AllowRedirect := True;
    PostData.Write(ZplData^, ZplLen);
    PostData.Position := 0;
    Client.RequestBody := PostData;
    Client.AddHeader('X-Rotation', IntToStr(Settings.rotation));
    try
      Client.Post(BuildURL(Settings), Output);
      Output.Position := 0;
      if Client.ResponseStatusCode = 200 then
        Result := True
      else begin
        if Output.Size < 100 then begin
          SetString(ErrorMsg, PAnsiChar(Output.Memory), Output.Size);
          FLastError := 'Labelary Error: ' + ErrorMsg;
        end else
          FLastError := 'Labelary Error: ' + Client.ResponseStatusText;
      end;
    except
      on E: Exception do
        FLastError := E.Message;
    end;
  finally
    FreeAndNil(PostData);
    FreeAndNil(Client);
  end;
end;

function TLabelaryRenderer.GetLastError: string;
begin
  Result := FLastError;
end;

end.

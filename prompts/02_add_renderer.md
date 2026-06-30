# Adding a New Render Engine

## Goal
Implement a new ZPL renderer (e.g. on-premise Labelary, local printer preview, or any REST service)
without touching `TForm1` or existing code.

## Steps

### 1. Create a new unit implementing `IZplRenderer`

```pascal
unit zplview_myrenderer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, zplview_settings, zplview_renderer;

type
  TMyRenderer = class(TInterfacedObject, IZplRenderer)
  private
    FLastError: string;
    FServiceURL: string;
  public
    constructor Create(const ServiceURL: string);
    function Render(ZplData: Pointer; ZplLen: Integer;
                    const Settings: ZViewSettings;
                    Output: TMemoryStream): Boolean;
    function GetLastError: string;
  end;

implementation

uses fphttpclient;

constructor TMyRenderer.Create(const ServiceURL: string);
begin
  inherited Create;
  FServiceURL := ServiceURL;
end;

function TMyRenderer.Render(ZplData: Pointer; ZplLen: Integer;
  const Settings: ZViewSettings; Output: TMemoryStream): Boolean;
var
  Client: TFPHTTPClient;
  PostData: TMemoryStream;
begin
  Result := False;
  FLastError := '';
  Client := TFPHTTPClient.Create(nil);
  PostData := TMemoryStream.Create;
  try
    PostData.Write(ZplData^, ZplLen);
    PostData.Position := 0;
    Client.RequestBody := PostData;
    // Add custom headers / auth as needed
    try
      Client.Post(FServiceURL, Output);
      Output.Position := 0;
      Result := Client.ResponseStatusCode = 200;
      if not Result then
        FLastError := 'Render error: ' + Client.ResponseStatusText;
    except
      on E: Exception do FLastError := E.Message;
    end;
  finally
    FreeAndNil(PostData);
    FreeAndNil(Client);
  end;
end;

function TMyRenderer.GetLastError: string;
begin
  Result := FLastError;
end;

end.
```

### 2. Swap the renderer in `TForm1.FormCreate`

```pascal
// Change this line in zplview_main.pas:
FRenderer := TLabelaryRenderer.Create;

// To:
FRenderer := TMyRenderer.Create('http://your-server/api/render');
```

### 3. (Optional) Drive renderer selection from settings

Add a `renderengine: integer` field to `ZViewSettings` and a factory function:

```pascal
function CreateRenderer(const Settings: ZViewSettings): IZplRenderer;
begin
  case Settings.renderengine of
    0: Result := TLabelaryRenderer.Create;           // Cloud free
    1: Result := TLabelaryRenderer.Create;           // On-premise (same class, different URL via settings)
    // 2: Result := TLocalPrinterRenderer.Create;
  else
    Result := TLabelaryRenderer.Create;
  end;
end;
```

## Contract

Any implementation of `IZplRenderer` must:
- Write a valid PNG to `Output` on success, return `True`
- Return `False` on any failure and populate `GetLastError` with a human-readable message
- NOT raise exceptions (catch internally, set FLastError)
- NOT modify `Settings`
- Be stateless between calls (thread-safe preferred)

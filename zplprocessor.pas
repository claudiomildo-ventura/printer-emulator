unit zplprocessor;

{$mode objfpc}{$H+}

{ Handles all communication with the Labelary REST API.

  The public entry point is FetchLabelImage: it posts raw ZPL bytes to
  api.labelary.com and writes the PNG response into a caller-supplied stream.

  On a successful 200 response, ImageData is positioned at 0 on return.
  On any API-level failure, ELabelaryError is raised.
  Network / transport failures propagate as the original exception.

  NOTE: FetchLabelImage blocks the calling thread for the duration of the HTTP
  round-trip. For responsive UI, the caller should invoke it from a background
  thread (TThread or TFPCustomThread) and marshal the result back to the main
  thread via Synchronize / TThread.Queue.
}

interface

uses
  Classes, SysUtils, fphttpclient, zplview_settings;

type
  ELabelaryError = class(Exception);

{ Posts ZplData to the Labelary API using the given Settings and fills
  ImageData with the PNG bytes of the rendered label.

  ZplData.Position is reset to 0 before reading.
  ImageData is cleared before writing.
  ImageData.Position is set to 0 on success.
  Raises ELabelaryError when the server returns a non-200 status.
  Raises ESocketError / EInOutError on network failure. }
procedure FetchLabelImage(const ZplData: TMemoryStream;
  const Settings: ZViewSettings; const ImageData: TMemoryStream);

{ Returns the fully-formed Labelary API URL for the given settings, e.g.
  http://api.labelary.com/v1/printers/8dpmm/labels/4.00x6.00/0/ }
function BuildLabelaryUrl(const Settings: ZViewSettings): string;

implementation

{ Maps a DPI integer to the Labelary printer identifier string. }
function ResolutionToDpiString(Resolution: Integer): string;
begin
  case Resolution of
    152: Result := '6dpmm';
    203: Result := '8dpmm';
    300: Result := '12dpmm';
    600: Result := '24dpmm';
  else
    Result := '8dpmm';
  end;
end;

function BuildLabelaryUrl(const Settings: ZViewSettings): string;
var
  FmtSettings: TFormatSettings;
begin
  { Force '.' as decimal separator so the URL is locale-independent. }
  FmtSettings := DefaultFormatSettings;
  FmtSettings.DecimalSeparator := '.';

  Result := Format('http://api.labelary.com/v1/printers/%s/labels/%nx%n/0/',
                   [ResolutionToDpiString(Settings.resolution),
                   Settings.Width,
                   Settings.Height],
                   FmtSettings);
end;

{ Extracts the response body from ImageData as a short error string.
  Only used when ResponseStatusCode <> 200 and the body is small. }
function ReadErrorBody(const ImageData: TMemoryStream): string;
begin
  SetLength(Result, ImageData.Size);
  if ImageData.Size > 0 then
  begin
    ImageData.Position := 0;
    ImageData.Read(Result[1], ImageData.Size);
  end;
end;

procedure FetchLabelImage(const ZplData: TMemoryStream;
  const Settings: ZViewSettings; const ImageData: TMemoryStream);
const
  { Response bodies larger than this are not included verbatim in errors. }
  MaxInlineErrorSize = 512;
var
  HttpClient: TFPHTTPClient;
  ErrorMsg: string;
begin
  HttpClient := TFPHTTPClient.Create(nil);
  try
    HttpClient.AllowRedirect := True;
    HttpClient.AddHeader('X-Rotation', IntToStr(Settings.rotation));

    ZplData.Position := 0;
    HttpClient.RequestBody := ZplData;

    ImageData.Clear;
    HttpClient.Post(BuildLabelaryUrl(Settings), ImageData);

    if HttpClient.ResponseStatusCode <> 200 then
    begin
      if ImageData.Size <= MaxInlineErrorSize then
        ErrorMsg := ReadErrorBody(ImageData)
      else
        ErrorMsg := HttpClient.ResponseStatusText;
      raise ELabelaryError.CreateFmt('Labelary API returned HTTP %d: %s', [HttpClient.ResponseStatusCode, ErrorMsg]);
    end;

    ImageData.Position := 0;
  finally
    FreeAndNil(HttpClient);
  end;
end;

end.

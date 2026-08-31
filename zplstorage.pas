unit zplstorage;

{$mode objfpc}{$H+}

{ Handles persistence of rendered label images and raw ZPL data.

  SaveLabelImage  — writes a timestamped PNG file to the given directory.
  SaveRawZplData  — writes (overwrites) rawdata.txt in the given directory.

  Both procedures accept an empty SavePath, in which case files are written to
  the application's current working directory. Platform-specific path separators
  are normalised automatically. }

interface

uses
  Classes, SysUtils, Graphics;

{ Saves Picture to <SavePath>/<timestamp>.png.
  If SavePath is empty, the file is placed in the current directory. }
procedure SaveLabelImage(Picture: TPicture; const SavePath: string);

{ Writes ZplText to <SavePath>/rawdata.txt, overwriting any existing file. }
procedure SaveRawZplData(const ZplText: string; const SavePath: string);

implementation

{ Normalises SavePath to a directory string with a trailing separator.
  Returns an empty string when SavePath is empty (caller gets cwd). }
function NormalisedSaveDir(const SavePath: string): string;
begin
  if SavePath = '' then
    Result := ''
  else
    Result := IncludeTrailingPathDelimiter(SetDirSeparators(SavePath));
end;

procedure EnsureSaveDirExists(const SaveDir: string);
begin
  if (SaveDir <> '') and (not DirectoryExists(SaveDir)) then
    ForceDirectories(SaveDir);
end;

procedure SaveLabelImage(Picture: TPicture; const SavePath: string);
var
  SaveDir, FileName: string;
begin
  SaveDir := NormalisedSaveDir(SavePath);
  EnsureSaveDirExists(SaveDir);
  FileName := Format('%s%s.png', [SaveDir, FormatDateTime('yyyymmdd_hhnnss_zzz', Now)]);
  Picture.SaveToFile(FileName);
end;

procedure SaveRawZplData(const ZplText: string; const SavePath: string);
var
  SaveDir, FileName: string;
  OutputStream: TStringStream;
begin
  SaveDir := NormalisedSaveDir(SavePath);
  EnsureSaveDirExists(SaveDir);
  FileName := SaveDir + 'rawdata.txt';
  OutputStream := TStringStream.Create(ZplText + LineEnding);
  try
    OutputStream.SaveToFile(FileName);
  finally
    OutputStream.Free;
  end;
end;

end.

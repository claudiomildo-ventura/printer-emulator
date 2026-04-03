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
  Classes, SysUtils, Graphics, dateutils;

{ Saves Picture to <SavePath>/<unix-timestamp>.png.
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

procedure SaveLabelImage(Picture: TPicture; const SavePath: string);
var
  FileName: string;
begin
  FileName := Format('%s%d.png', [NormalisedSaveDir(SavePath), DateTimeToUnix(Now)]);
  Picture.SaveToFile(FileName);
end;

procedure SaveRawZplData(const ZplText: string; const SavePath: string);
var
  FileName: string;
  OutputFile: TextFile;
begin
  FileName := NormalisedSaveDir(SavePath) + 'rawdata.txt';
  AssignFile(OutputFile, FileName);
  try
    Rewrite(OutputFile);
    Writeln(OutputFile, ZplText);
  finally
    CloseFile(OutputFile);
  end;
end;

end.

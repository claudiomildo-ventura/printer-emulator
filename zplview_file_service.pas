unit zplview_file_service;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, dateutils, zplview_settings;

type
  TZplFileService = class
  public
    procedure SavePng(Picture: TPicture; const Settings: ZViewSettings);
    procedure SaveRaw(const Data: string; const Settings: ZViewSettings);
  end;

implementation

procedure TZplFileService.SavePng(Picture: TPicture; const Settings: ZViewSettings);
var
  FileName: string;
begin
  FileName := Settings.savepath;
  if FileName <> '' then FileName := FileName + '/';
  FileName := Format('%s%d.png', [SetDirSeparators(FileName), DateTimeToUnix(Now)]);
  Picture.SaveToFile(FileName);
end;

procedure TZplFileService.SaveRaw(const Data: string; const Settings: ZViewSettings);
var
  F: TextFile;
  FileName: string;
begin
  FileName := Settings.savepath;
  if FileName <> '' then FileName := FileName + '/';
  FileName := Format('%srawdata.txt', [SetDirSeparators(FileName)]);
  AssignFile(F, FileName);
  try
    Rewrite(F);
    Writeln(F, Data);
  finally
    CloseFile(F);
  end;
end;

end.

unit zplview_settings_manager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, INIFiles, zplview_settings;

type
  TZplSettingsManager = class
  private
    FIniFilePath: string;
    function ResolveIniFilePath: string;
  public
    constructor Create;
    procedure LoadDefaults(out Settings: ZViewSettings);
    procedure Load(out Settings: ZViewSettings);
    procedure Save(const Settings: ZViewSettings);
    function GetLANIp: string;
    property IniFilePath: string read FIniFilePath;
  end;

implementation

uses
  Sockets, ssockets;

constructor TZplSettingsManager.Create;
begin
  inherited;
  FIniFilePath := ResolveIniFilePath;
end;

function TZplSettingsManager.ResolveIniFilePath: string;
var
  FileName: string;
begin
  FileName := ChangeFileExt(ExtractFileName(ParamStr(0)), '.ini');
  if GetEnvironmentVariable('APPDATA') <> '' then
    Result := GetEnvironmentVariable('APPDATA') + '\' + FileName
  else if GetEnvironmentVariable('HOME') <> '' then
    Result := GetEnvironmentVariable('HOME') + '/.config/' + FileName
  else
    Result := FileName;
end;

procedure TZplSettingsManager.LoadDefaults(out Settings: ZViewSettings);
begin
  with Settings do begin
    resolution    := 203;
    rotation      := 0;
    width         := 4.0;
    height        := 3.0;
    save          := False;
    savepath      := '';
    print         := False;
    printraw      := False;
    printer       := '';
    executescript := False;
    saverawdata   := False;
    scriptpath    := '';
    tcpport       := 9100;
    bindadr       := '0.0.0.0';
  end;
end;

procedure TZplSettingsManager.Load(out Settings: ZViewSettings);
var
  INI: TINIFile;
begin
  INI := TINIFile.Create(FIniFilePath);
  try
    with Settings do begin
      resolution    := INI.ReadInteger('SETTINGS', 'resolution', 203);
      rotation      := INI.ReadInteger('SETTINGS', 'rotation', 0);
      width         := INI.ReadFloat('SETTINGS', 'width', 4.0);
      height        := INI.ReadFloat('SETTINGS', 'height', 3.0);
      save          := INI.ReadBool('SETTINGS', 'save', False);
      savepath      := INI.ReadString('SETTINGS', 'savepath', '');
      print         := INI.ReadBool('SETTINGS', 'print', False);
      printraw      := INI.ReadBool('SETTINGS', 'printraw', False);
      printer       := INI.ReadString('SETTINGS', 'printer', '');
      executescript := INI.ReadBool('SETTINGS', 'executescript', False);
      saverawdata   := INI.ReadBool('SETTINGS', 'saverawdata', False);
      scriptpath    := INI.ReadString('SETTINGS', 'scriptpath', '');
      tcpport       := INI.ReadInteger('SETTINGS', 'tcpport', 9100);
      bindadr       := INI.ReadString('SETTINGS', 'bindadr', '0.0.0.0');
    end;
  finally
    INI.Free;
  end;
end;

procedure TZplSettingsManager.Save(const Settings: ZViewSettings);
var
  INI: TINIFile;
begin
  INI := TINIFile.Create(FIniFilePath);
  try
    with Settings do begin
      INI.WriteInteger('SETTINGS', 'resolution', resolution);
      INI.WriteInteger('SETTINGS', 'rotation', rotation);
      INI.WriteFloat('SETTINGS', 'width', width);
      INI.WriteFloat('SETTINGS', 'height', height);
      INI.WriteBool('SETTINGS', 'save', save);
      INI.WriteString('SETTINGS', 'savepath', savepath);
      INI.WriteBool('SETTINGS', 'print', print);
      INI.WriteBool('SETTINGS', 'printraw', printraw);
      INI.WriteString('SETTINGS', 'printer', printer);
      INI.WriteBool('SETTINGS', 'executescript', executescript);
      INI.WriteBool('SETTINGS', 'saverawdata', saverawdata);
      INI.WriteString('SETTINGS', 'scriptpath', scriptpath);
      INI.WriteInteger('SETTINGS', 'tcpport', tcpport);
      INI.WriteString('SETTINGS', 'bindadr', bindadr);
    end;
  finally
    INI.Free;
  end;
end;

function TZplSettingsManager.GetLANIp: string;
var
  S: TInetSocket;
begin
  Result := '127.0.0.1';
  try
    S := TInetSocket.Create('1.1.1.1', 80);
    try
      Result := NetAddrToStr(S.LocalAddress.sin_addr);
    finally
      S.Free;
    end;
  except
    // Retorna padrão se a rede não estiver disponível
  end;
end;

end.

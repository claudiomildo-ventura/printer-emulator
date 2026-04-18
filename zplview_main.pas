unit zplview_main;

{$mode objfpc}{$H+}

{ Main form — responsible only for UI concerns.
  Network reception  : zplnet      (TZplTcpServer)
  Labelary API calls : zplprocessor (FetchLabelImage)
  File persistence   : zplstorage  (SaveLabelImage, SaveRawZplData) }

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ExtCtrls,
  StdCtrls, ComCtrls, Sockets, ssockets, zplview_settings, zplnet,
  zplprocessor, zplstorage, dateutils, INIFiles, Printers, lazlogger,
  DefaultTranslator;

type

  { TFrmPrintEmulator }

  TFrmPrintEmulator = class(TForm)
    BRenderManual: TButton;
    Image1: TImage;
    MainMenu1: TMainMenu;
    MSourceCode: TMemo;
    MenuItem1: TMenuItem;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    AcceptTimer: TTimer;
    Panel1: TPanel;
    Panel2: TPanel;
    Shape1: TShape;
    StatusBar1: TStatusBar;
    TBLock: TToggleBox;
    procedure AcceptTimerTimer(Sender: TObject);
    procedure BRenderManualClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure MenuItem2Click(Sender: TObject);
    procedure MenuItem3Click(Sender: TObject);
    procedure MSourceCodeChange(Sender: TObject);
    procedure Panel2Click(Sender: TObject);
    procedure StatusBar1Click(Sender: TObject);
  private
    { Network server — polls on AcceptTimer tick }
    FTcpServer: TZplTcpServer;
    { Persistent copy of the last received (or manually entered) ZPL job }
    FZplData: TMemoryStream;
    { Ruler drag state }
    FDragDir: integer;
    FRulers: array of integer;
    FRulerTypes: array of integer; // 0 = vertical, 1 = horizontal
    FRulersVisible: boolean;
    { Application settings }
    FSettings: ZViewSettings;
    FJobCount: integer;
    FIniFilePath: string;

    { Called by FTcpServer when a complete ZPL job arrives over TCP }
    procedure HandleZplDataReceived(const ZplData: TMemoryStream);

    { Submits FZplData to the Labelary API and updates the display }
    procedure FetchAndDisplayLabel;

    { Print FZplData / current image on the configured printer }
    procedure RePrint;

    { Settings persistence }
    procedure LoadSettings;
    procedure SaveSettings;
    procedure ResetSettings;

    function IniFilePath: string;
    function GetLANIP: string;

    { Rebuild the TCP server using current FSettings (port / bind address) }
    procedure RecreateServer;
  public

  end;

var
  FrmPrintEmulator: TFrmPrintEmulator;

implementation

{$R *.lfm}

{ TFrmPrintEmulator }

function TFrmPrintEmulator.GetLANIP: string;
var
  Socket: TInetSocket;
begin
  Result := '';
  Socket := TInetSocket.Create('1.1.1.1', 80);
  try
    Result := NetAddrToStr(Socket.LocalAddress.sin_addr);
  finally
    Socket.Free;
  end;
end;

function TFrmPrintEmulator.IniFilePath: string;
var
  BaseName, EnvDir: string;
begin
  BaseName := ChangeFileExt(ExtractFileName(Application.ExeName), '.ini');

  EnvDir := GetEnvironmentVariable('APPDATA');
  if EnvDir <> '' then
    Exit(IncludeTrailingPathDelimiter(EnvDir) + BaseName);

  EnvDir := GetEnvironmentVariable('HOME');
  if EnvDir <> '' then
    Exit(IncludeTrailingPathDelimiter(EnvDir) + '.config' + PathDelim + BaseName);

  Result := BaseName;
end;

procedure TFrmPrintEmulator.FormCreate(Sender: TObject);
begin
  FZplData := TMemoryStream.Create;
  FJobCount := 0;

  FIniFilePath := IniFilePath;
  ResetSettings;
  LoadSettings;

  if StatusBar1.Panels.Count > 3 then
    StatusBar1.Panels[3].Text := GetLANIP + ':' + IntToStr(FSettings.tcpport);

  FTcpServer := TZplTcpServer.Create(FSettings.bindadr, FSettings.tcpport);
  FTcpServer.OnDataReceived := @HandleZplDataReceived;

  SetLength(FRulers, 0);
  SetLength(FRulerTypes, 0);
  FDragDir := -1;
  FRulersVisible := True;
  Panel1.Width := 15;

  Self.Position := poScreenCenter;
end;

procedure TFrmPrintEmulator.AcceptTimerTimer(Sender: TObject);
begin
  FTcpServer.Poll;
end;

procedure TFrmPrintEmulator.BRenderManualClick(Sender: TObject);
var
  ZplText: string;
begin
  if MSourceCode.Lines.Count > 3 then
  begin
    ZplText := MSourceCode.Lines.Text;
    FZplData.Clear;

    if Length(ZplText) > 0 then
      FZplData.WriteBuffer(ZplText[1], Length(ZplText));

    FZplData.Position := 0;
    FetchAndDisplayLabel;
  end;
end;

procedure TFrmPrintEmulator.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  FreeAndNil(FTcpServer);
  FreeAndNil(FZplData);
end;

procedure TFrmPrintEmulator.MenuItem2Click(Sender: TObject);
begin
  FrmPrintEmulatorSettings.PutSettings(FSettings);

  if FrmPrintEmulatorSettings.ShowModal = mrOk then
  begin
    FrmPrintEmulatorSettings.GetSettings(FSettings);

    StatusBar1.Panels[1].Text := IntToStr(FSettings.rotation);

    if StatusBar1.Panels.Count > 3 then
      StatusBar1.Panels[3].Text := GetLANIP + ':' + IntToStr(FSettings.tcpport);

    SaveSettings;

    if FZplData.Size > 0 then
      FetchAndDisplayLabel;

    if FTcpServer.Port <> FSettings.tcpport then
      RecreateServer;
  end;
end;

procedure TFrmPrintEmulator.MenuItem3Click(Sender: TObject);
begin
  Close;
end;

procedure TFrmPrintEmulator.MSourceCodeChange(Sender: TObject);
begin
  TBLock.Checked := (MSourceCode.Lines.Count > 3);
end;

procedure TFrmPrintEmulator.Panel2Click(Sender: TObject);
var
  NewWidth: Integer;
begin
  if Panel1.Width < 50 then
    NewWidth := 150
  else
    NewWidth := 15;

  if Panel1.Width <> NewWidth then
  begin
    Panel1.DisableAlign;
    try
      Panel1.Width := NewWidth;
    finally
      Panel1.EnableAlign;
    end;
  end;
end;

procedure TFrmPrintEmulator.StatusBar1Click(Sender: TObject);
begin
  FSettings.rotation := FSettings.rotation + 90;
  if FSettings.rotation > 270 then
    FSettings.rotation := 0;

  StatusBar1.Panels[1].Text := IntToStr(FSettings.rotation);

  if FZplData.Size > 0 then
    FetchAndDisplayLabel;
end;

procedure TFrmPrintEmulator.RePrint;
var
  PrinterIndex, BytesWritten: integer;
begin
  PrinterIndex := Printer.Printers.IndexOf(FSettings.printer);

  if PrinterIndex < 0 then
  begin
    MessageDlg('Printer not found', 'Selected printer "' + FSettings.printer + '" was not found.', mtError, [mbOK], 0);
    Exit;
  end;

  if FZplData.Size = 0 then
  begin
    MessageDlg('Nothing to print', 'There is no ZPL data to print.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if (not FSettings.printraw) and (Image1.Picture.Graphic = nil) then
  begin
    MessageDlg('Print error', 'No rendered image available.', mtError, [mbOK], 0);
    Exit;
  end;

  Printer.PrinterIndex := PrinterIndex;

  if Printer.Printing then
    Printer.Abort;

  try
    Printer.Title := 'ZPL-View reprint';
    Printer.RawMode := FSettings.printraw;
    Printer.BeginDoc;

    if FSettings.printraw then
      Printer.Write(FZplData.Memory^, FZplData.Size, BytesWritten)
    else
      Printer.Canvas.StretchDraw(
        Classes.Rect(0, 0,
          Image1.Picture.Graphic.Width * Printer.XDPI div FSettings.resolution,
          Image1.Picture.Graphic.Height * Printer.YDPI div FSettings.resolution),
        Image1.Picture.Graphic);
  finally
    Printer.EndDoc;
  end;
end;

procedure TFrmPrintEmulator.FetchAndDisplayLabel;
var
  ImageData: TMemoryStream;
begin
  Image1.Picture.Clear;
  Image1.Invalidate;
  Application.ProcessMessages;

  ImageData := TMemoryStream.Create;
  try
    try
      FetchLabelImage(FZplData, FSettings, ImageData);
    except
      on E: Exception do
      begin
        MessageDlg('Render error', E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;

    Image1.Picture.LoadFromStream(ImageData);

    Inc(FJobCount);
    StatusBar1.Panels[0].Text := Format('#%d - %s', [FJobCount, DateTimeToStr(Now)]);

    if FSettings.save then
      SaveLabelImage(Image1.Picture, FSettings.savepath);

    if FSettings.print then
      RePrint;

  finally
    ImageData.Free;
  end;
end;

procedure TFrmPrintEmulator.HandleZplDataReceived(const ZplData: TMemoryStream);
var
  ZplText: string;
begin
  FZplData.Clear;
  ZplData.Position := 0;
  FZplData.CopyFrom(ZplData, ZplData.Size);
  FZplData.Position := 0;

  if FZplData.Size > 0 then
    SetString(ZplText, PAnsiChar(FZplData.Memory), FZplData.Size)
  else
    ZplText := '';

  DebugLn(DateTimeToStr(Now));
  DebugLn(ZplText);

  if not TBLock.Checked then
    MSourceCode.Text := ZplText;

  if FSettings.saverawdata then
    SaveRawZplData(ZplText, FSettings.savepath);

  FetchAndDisplayLabel;
end;

procedure TFrmPrintEmulator.RecreateServer;
begin
  if Assigned(FTcpServer) then
    FreeAndNil(FTcpServer);

  FTcpServer := TZplTcpServer.Create(FSettings.bindadr, FSettings.tcpport);
  FTcpServer.OnDataReceived := @HandleZplDataReceived;
end;

procedure TFrmPrintEmulator.LoadSettings;
var
  INI: TINIFile;
begin
  INI := TINIFile.Create(FIniFilePath);
  try
    FSettings.resolution := INI.ReadInteger('SETTINGS', 'resolution', 203);
    FSettings.rotation := INI.ReadInteger('SETTINGS', 'rotation', 0);
    FSettings.Width := INI.ReadFloat('SETTINGS', 'width', 4.0);
    FSettings.Height := INI.ReadFloat('SETTINGS', 'height', 3.0);
    FSettings.save := INI.ReadBool('SETTINGS', 'save', False);
    FSettings.savepath := INI.ReadString('SETTINGS', 'savepath', '');
    FSettings.print := INI.ReadBool('SETTINGS', 'print', False);
    FSettings.printraw := INI.ReadBool('SETTINGS', 'printraw', False);
    FSettings.printer := INI.ReadString('SETTINGS', 'printer', '');
    FSettings.executescript := INI.ReadBool('SETTINGS', 'executescript', False);
    FSettings.saverawdata := INI.ReadBool('SETTINGS', 'saverawdata', False);
    FSettings.scriptpath := INI.ReadString('SETTINGS', 'scriptpath', '');
    FSettings.tcpport := INI.ReadInteger('SETTINGS', 'tcpport', 9100);
    FSettings.bindadr := INI.ReadString('SETTINGS', 'bindadr', '0.0.0.0');
  finally
    INI.Free;
  end;
end;

procedure TFrmPrintEmulator.SaveSettings;
var
  INI: TINIFile;
begin
  INI := TINIFile.Create(FIniFilePath);
  try
    INI.WriteInteger('SETTINGS', 'resolution', FSettings.resolution);
    INI.WriteInteger('SETTINGS', 'rotation', FSettings.rotation);
    INI.WriteFloat('SETTINGS', 'width', FSettings.Width);
    INI.WriteFloat('SETTINGS', 'height', FSettings.Height);
    INI.WriteBool('SETTINGS', 'save', FSettings.save);
    INI.WriteString('SETTINGS', 'savepath', FSettings.savepath);
    INI.WriteBool('SETTINGS', 'print', FSettings.print);
    INI.WriteBool('SETTINGS', 'printraw', FSettings.printraw);
    INI.WriteString('SETTINGS', 'printer', FSettings.printer);
    INI.WriteBool('SETTINGS', 'executescript', FSettings.executescript);
    INI.WriteBool('SETTINGS', 'saverawdata', FSettings.saverawdata);
    INI.WriteString('SETTINGS', 'scriptpath', FSettings.scriptpath);
    INI.WriteInteger('SETTINGS', 'tcpport', FSettings.tcpport);
    INI.WriteString('SETTINGS', 'bindadr', FSettings.bindadr);
  finally
    INI.Free;
  end;
end;

procedure TFrmPrintEmulator.ResetSettings;
begin
  FSettings.resolution := 203;
  FSettings.rotation := 0;
  FSettings.Width := 4.0;
  FSettings.Height := 3.0;
  FSettings.save := False;
  FSettings.savepath := '';
  FSettings.print := False;
  FSettings.printraw := False;
  FSettings.printer := '';
  FSettings.executescript := False;
  FSettings.saverawdata := False;
  FSettings.scriptpath := '';
  FSettings.tcpport := 9100;
  FSettings.bindadr := '0.0.0.0';
end;

end.

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

  { TForm1 }

  TForm1 = class(TForm)
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
    procedure Image1DragDrop(Sender, Source: TObject; X, Y: integer);
    procedure Image1DragOver(Sender, Source: TObject; X, Y: integer; State: TDragState; var Accept: boolean);
    procedure Image1Paint(Sender: TObject);
    procedure Image1StartDrag(Sender: TObject; var DragObject: TDragObject);
    procedure MenuItem2Click(Sender: TObject);
    procedure MenuItem3Click(Sender: TObject);
    procedure MSourceCodeChange(Sender: TObject);
    procedure Panel2Click(Sender: TObject);
    procedure Shape1EndDrag(Sender, Target: TObject; X, Y: integer);
    procedure Shape1MouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure Shape1MouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure Shape1StartDrag(Sender: TObject; var DragObject: TDragObject);
    procedure StatusBar1Click(Sender: TObject);
    procedure TBLockChange(Sender: TObject);
  private
    { Network server — polls on AcceptTimer tick }
    FTcpServer: TZplTcpServer;
    { Persistent copy of the last received (or manually entered) ZPL job }
    FZplData: TMemoryStream;
    { Ruler drag state }
    FDragDir: integer;
    FDragData: integer;
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
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

function TForm1.GetLANIP: string;
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

function TForm1.IniFilePath: string;
var
  BaseName: string;
  EnvDir: string;
begin
  BaseName := ChangeFileExt(ExtractFileName(Application.ExeName), '.ini');
  EnvDir := GetEnvironmentVariable('APPDATA');
  if EnvDir <> '' then
    Result := IncludeTrailingPathDelimiter(EnvDir) + BaseName
  else
  begin
    EnvDir := GetEnvironmentVariable('HOME');
    if EnvDir <> '' then
      Result := IncludeTrailingPathDelimiter(EnvDir) + '.config' + PathDelim + BaseName
    else
      Result := BaseName;
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  FZplData := TMemoryStream.Create;
  FJobCount := 0;

  FIniFilePath := IniFilePath;
  ResetSettings;
  LoadSettings;
  StatusBar1.Panels[3].Text := GetLANIP + ':' + IntToStr(FSettings.tcpport);

  FTcpServer := TZplTcpServer.Create(FSettings.bindadr, FSettings.tcpport);
  FTcpServer.OnDataReceived := @HandleZplDataReceived;

  SetLength(FRulers, 0);
  SetLength(FRulerTypes, 0);
  FDragDir := -1;
  FRulersVisible := True;
  Panel1.Width := 15;
end;

procedure TForm1.Image1DragDrop(Sender, Source: TObject; X, Y: integer);
var
  ImagePixelPos: longint;
begin
  if ((Source = Shape1) and (FDragDir > -1) and (Image1.Picture.Graphic <> nil)) then
  begin
    SetLength(FRulers, Length(FRulers) + 1);
    SetLength(FRulerTypes, Length(FRulerTypes) + 1);
    FRulerTypes[High(FRulerTypes)] := FDragDir;
    ImagePixelPos := FDragData * Image1.Picture.Width div Image1.Width;
    FRulers[High(FRulers)] := ImagePixelPos;
    FDragDir := -1;
    StatusBar1.Panels[2].Text := '';
    Image1.Repaint;
  end;
end;

procedure TForm1.Image1DragOver(Sender, Source: TObject; X, Y: integer; State: TDragState; var Accept: boolean);
var
  CursorPos: TPoint;
begin
  if (Source = Shape1) then
  begin
    Accept := True;
    FRulersVisible := True;
    CursorPos := ScreenToClient(Mouse.CursorPos);
    if FDragDir = -1 then
    begin
      if CursorPos.X >= 15 then FDragDir := 0;  // horizontal ruler
      if CursorPos.Y >= 15 then FDragDir := 1;  // vertical ruler
    end;
    if FDragDir = 0 then
    begin
      StatusBar1.Panels[2].Text := 'X = ' + IntToStr(CursorPos.X);
      FDragData := CursorPos.X;
    end;
    if FDragDir = 1 then
    begin
      StatusBar1.Panels[2].Text := 'Y = ' + IntToStr(CursorPos.Y);
      FDragData := CursorPos.Y;
    end;
    Image1.Repaint;
  end;
end;

procedure TForm1.Image1Paint(Sender: TObject);
var
  n: integer;
  DisplayPos: longint;
begin
  if FRulersVisible and (Image1.Picture.Graphic <> nil) then
  begin
    if Length(FRulerTypes) > 0 then
    begin
      Image1.Canvas.Pen.Color := clGreen;
      for n := 0 to High(FRulerTypes) do
      begin
        DisplayPos := FRulers[n] * Image1.Width div Image1.Picture.Width;
        if FRulerTypes[n] = 0 then
        begin
          Image1.Canvas.MoveTo(DisplayPos, 0);
          Image1.Canvas.LineTo(DisplayPos, Image1.Canvas.Height);
        end;
        if FRulerTypes[n] = 1 then
        begin
          Image1.Canvas.MoveTo(0, DisplayPos);
          Image1.Canvas.LineTo(Image1.Canvas.Width, DisplayPos);
        end;
      end;
    end;
    if FDragDir > -1 then
    begin
      Image1.Canvas.Pen.Color := clRed;
      if FDragDir = 0 then
      begin
        Image1.Canvas.MoveTo(FDragData, 0);
        Image1.Canvas.LineTo(FDragData, Image1.Canvas.Height);
      end;
      if FDragDir = 1 then
      begin
        Image1.Canvas.MoveTo(0, FDragData);
        Image1.Canvas.LineTo(Image1.Canvas.Width, FDragData);
      end;
    end;
  end;
end;

procedure TForm1.Image1StartDrag(Sender: TObject; var DragObject: TDragObject);
begin

end;

procedure TForm1.MenuItem2Click(Sender: TObject);
begin
  FormSettings.PutSettings(FSettings);
  if FormSettings.ShowModal = mrOk then
  begin
    FormSettings.GetSettings(FSettings);
    StatusBar1.Panels[1].Text := IntToStr(FSettings.rotation);
    StatusBar1.Panels[3].Text := GetLANIP + ':' + IntToStr(FSettings.tcpport);
    SaveSettings;
    if FZplData.Size > 0 then FetchAndDisplayLabel;
    if FTcpServer.Port <> FSettings.tcpport then
      RecreateServer;
  end;
end;

procedure TForm1.MenuItem3Click(Sender: TObject);
begin
  Form1.Close;
end;

procedure TForm1.MSourceCodeChange(Sender: TObject);
begin
  TBLock.Checked := (MSourceCode.Lines.Count > 3);
end;

procedure TForm1.Panel2Click(Sender: TObject);
begin
  if Panel1.Width < 50 then
  begin
    Form1.Width := Form1.Width + Form1.Width;
    Panel1.Width := Panel1.Width + (Form1.Width div 2);
  end
  else
  begin
    Form1.Width := Form1.Width div 2;
    Panel1.Width := 15;
  end;
end;

procedure TForm1.Shape1EndDrag(Sender, Target: TObject; X, Y: integer);
begin
  FDragDir := -1;
  Image1.Repaint;
end;

procedure TForm1.Shape1MouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  if (Button = mbLeft) and (Image1.Picture.Graphic <> nil) then
  begin
    Shape1.BeginDrag(False);
    if not FRulersVisible then
    begin
      FRulersVisible := True;
      Image1.Repaint;
    end;
  end;
  if Button = mbRight then
  begin
    SetLength(FRulers, 0);
    SetLength(FRulerTypes, 0);
    Image1.Repaint;
  end;
end;

procedure TForm1.Shape1MouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  if (Button = mbLeft) and (X < Shape1.Width) and (Y < Shape1.Height) then
  begin
    FRulersVisible := False;
    Image1.Repaint;
  end;
end;

procedure TForm1.Shape1StartDrag(Sender: TObject; var DragObject: TDragObject);
begin
  FDragDir := -1;
  FRulersVisible := True;
end;

procedure TForm1.StatusBar1Click(Sender: TObject);
begin
  with FSettings do
  begin
    rotation := rotation + 90;
    if rotation > 270 then rotation := 0;
    StatusBar1.Panels[1].Text := IntToStr(rotation);
  end;
  if FZplData.Size > 0 then FetchAndDisplayLabel;
end;

procedure TForm1.TBLockChange(Sender: TObject);
begin

end;

procedure TForm1.AcceptTimerTimer(Sender: TObject);
begin
  FTcpServer.Poll;
end;

procedure TForm1.BRenderManualClick(Sender: TObject);
var
  ZplText: string;
begin
  if MSourceCode.Lines.Count > 3 then
  begin
    ZplText := MSourceCode.Lines.Text;
    FZplData.Clear;
    if Length(ZplText) > 0 then
      FZplData.Write(ZplText[1], Length(ZplText));
    FZplData.Position := 0;
    FetchAndDisplayLabel;
  end;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  FreeAndNil(FTcpServer);
  FreeAndNil(FZplData);
end;

procedure TForm1.RePrint;
var
  PrinterIndex: integer;
  BytesWritten: integer;
begin
  PrinterIndex := Printer.Printers.IndexOf(FSettings.printer);
  if PrinterIndex < 0 then
  begin
    MessageDlg('Printer not found',
      'Selected printer "' + FSettings.printer + '" was not found.',
      mtError, [mbOK], 0);
    Exit;
  end;
  if FZplData.Size = 0 then
  begin
    MessageDlg('Nothing to print',
      'There is no ZPL data to print.',
      mtWarning, [mbOK], 0);
    Exit;
  end;
  Printer.PrinterIndex := PrinterIndex;
  if Printer.Printing then Printer.Abort;
  try
    Printer.Title := 'ZPL-View reprint';
    Printer.RawMode := FSettings.printraw;
    Printer.BeginDoc;
    if FSettings.printraw then
      Printer.Write(FZplData.Memory^, FZplData.Size, BytesWritten)
    else
      Printer.Canvas.StretchDraw(
        Classes.Rect(0, 0, Image1.Picture.Graphic.Width * Printer.XDPI div FSettings.resolution, Image1.Picture.Graphic.Height * Printer.YDPI div FSettings.resolution),
        Image1.Picture.Graphic);
  finally
    Printer.EndDoc;
  end;
end;

procedure TForm1.FetchAndDisplayLabel;
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
    if FSettings.save then SaveLabelImage(Image1.Picture, FSettings.savepath);
    if FSettings.print then RePrint;
  finally
    FreeAndNil(ImageData);
  end;
end;

procedure TForm1.HandleZplDataReceived(const ZplData: TMemoryStream);
var
  ZplText: string;
begin
  { Copy the incoming job into our persistent buffer for reprints / re-renders }
  FZplData.Clear;
  ZplData.Position := 0;
  FZplData.CopyFrom(ZplData, ZplData.Size);
  FZplData.Position := 0;

  { Extract as text for display and logging }
  SetString(ZplText, pansichar(FZplData.Memory), FZplData.Size);
  DebugLn(DateTimeToStr(Now));
  DebugLn(ZplText);

  if not TBLock.Checked then
    MSourceCode.Text := ZplText;

  if FSettings.saverawdata then
    SaveRawZplData(ZplText, FSettings.savepath);

  FetchAndDisplayLabel;
end;

procedure TForm1.RecreateServer;
begin
  FreeAndNil(FTcpServer);
  FTcpServer := TZplTcpServer.Create(FSettings.bindadr, FSettings.tcpport);
  FTcpServer.OnDataReceived := @HandleZplDataReceived;
end;

procedure TForm1.LoadSettings;
var
  INI: TINIFile;
begin
  INI := TINIFile.Create(FIniFilePath);
  try
    with FSettings do
    begin
      resolution := INI.ReadInteger('SETTINGS', 'resolution', 203);
      rotation := INI.ReadInteger('SETTINGS', 'rotation', 0);
      Width := INI.ReadFloat('SETTINGS', 'width', 4.0);
      Height := INI.ReadFloat('SETTINGS', 'height', 3.0);
      save := INI.ReadBool('SETTINGS', 'save', False);
      savepath := INI.ReadString('SETTINGS', 'savepath', '');
      print := INI.ReadBool('SETTINGS', 'print', False);
      printraw := INI.ReadBool('SETTINGS', 'printraw', False);
      printer := INI.ReadString('SETTINGS', 'printer', '');
      executescript := INI.ReadBool('SETTINGS', 'executescript', False);
      saverawdata := INI.ReadBool('SETTINGS', 'saverawdata', False);
      scriptpath := INI.ReadString('SETTINGS', 'scriptpath', '');
      tcpport := INI.ReadInteger('SETTINGS', 'tcpport', 9100);
      bindadr := INI.ReadString('SETTINGS', 'bindadr', '0.0.0.0');
    end;
  finally
    INI.Free;
  end;
end;

procedure TForm1.SaveSettings;
var
  INI: TINIFile;
begin
  INI := TINIFile.Create(FIniFilePath);
  try
    with FSettings do
    begin
      INI.WriteInteger('SETTINGS', 'resolution', resolution);
      INI.WriteInteger('SETTINGS', 'rotation', rotation);
      INI.WriteFloat('SETTINGS', 'width', Width);
      INI.WriteFloat('SETTINGS', 'height', Height);
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

procedure TForm1.ResetSettings;
begin
  with FSettings do
  begin
    resolution := 203;
    rotation := 0;
    Width := 4.0;
    Height := 3.0;
    save := False;
    savepath := '';
    print := False;
    printraw := False;
    printer := '';
    executescript := False;
    saverawdata := False;
    scriptpath := '';
    tcpport := 9100;
    bindadr := '0.0.0.0';
  end;
end;

end.

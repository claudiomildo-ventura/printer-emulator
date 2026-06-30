unit zplview_main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ExtCtrls,
  StdCtrls, ComCtrls, ssockets, zplview_settings, lazlogger, DefaultTranslator,
  zplview_renderer, zplview_settings_manager, zplview_file_service,
  zplview_print_service;

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
    procedure Image1DragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure Image1DragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure Image1Paint(Sender: TObject);
    procedure Image1StartDrag(Sender: TObject; var DragObject: TDragObject);
    procedure MenuItem2Click(Sender: TObject);
    procedure MenuItem3Click(Sender: TObject);
    procedure MSourceCodeChange(Sender: TObject);
    procedure Panel2Click(Sender: TObject);
    procedure Shape1EndDrag(Sender, Target: TObject; X, Y: Integer);
    procedure Shape1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure Shape1MouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure Shape1StartDrag(Sender: TObject; var DragObject: TDragObject);
    procedure StatusBar1Click(Sender: TObject);
    procedure TBLockChange(Sender: TObject);
  private
    FSocket: TINetServer;
    FSettingsManager: TZplSettingsManager;
    FRenderer: IZplRenderer;
    FFileService: TZplFileService;
    FPrintService: TZplPrintService;
    zpldata: Pointer;
    zpldatalen: LongInt;
    dragDir: Integer;
    dragData: Integer;
    rulers: array of integer;
    rulertypes: array of integer; // 0=Vertical, 1=horizontal
    RulersVisible: Boolean;
    settings: ZViewSettings;
    jobCnt: Integer;
    procedure ReadJetData(Sender: TObject; DataStream: TSocketStream);
    procedure RenderAndDisplay;
    procedure NothingHappened(Sender: TObject);
    procedure InitSocket;
    procedure FreeSocket;
  public

  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.InitSocket;
begin
  FSocket := TINetServer.Create(settings.bindadr, settings.tcpport);
  FSocket.ReuseAddress := True;
  FSocket.MaxConnections := 1;
  FSocket.OnConnect := @ReadJetData;
  FSocket.OnIdle := @NothingHappened;
  FSocket.Bind;
  FSocket.Listen;
  FSocket.AcceptIdleTimeOut := 100;
end;

procedure TForm1.FreeSocket;
begin
  FreeAndNil(FSocket);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  GetMem(zpldata, 1000000);
  FillChar(zpldata^, 1000000, 0);
  zpldatalen := 0;
  jobCnt := 0;

  FSettingsManager := TZplSettingsManager.Create;
  FSettingsManager.LoadDefaults(settings);
  FSettingsManager.Load(settings);
  FRenderer := TLabelaryRenderer.Create;
  FFileService := TZplFileService.Create;
  FPrintService := TZplPrintService.Create;

  StatusBar1.Panels[3].Text := FSettingsManager.GetLANIp + ':' + IntToStr(settings.tcpport);
  InitSocket;

  SetLength(rulers, 0);
  SetLength(rulertypes, 0);
  DragDir := -1;
  RulersVisible := True;
  Panel1.Width := 15;
end;

procedure TForm1.Image1DragDrop(Sender, Source: TObject; X, Y: Integer);
var
  aspect: LongInt;
begin
  if ((Source = Shape1) and (DragDir>-1) and (Image1.Picture.Graphic<>nil) ) then
  begin
    // Drop it like its hot...
    SetLength(rulers,Length(rulers)+1);
    SetLength(rulertypes,Length(rulertypes)+1);
    rulertypes[Length(rulertypes)-1]:=DragDir;
    aspect:= DragData*Image1.Picture.Width div Image1.Width;
    rulers[Length(rulers)-1]:=aspect;
    DragDir:=-1;
    StatusBar1.Panels[2].Text:='';
    Image1.Repaint;
  end;
end;

procedure TForm1.Image1DragOver(Sender, Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
var
  pt : tPoint;
begin
  if (Source = Shape1) then
  begin
    Accept := True;
    RulersVisible:=True;
    pt := ScreenToClient(Mouse.CursorPos);
    if DragDir=-1 then
    begin
      // now have FORM position
      if pt.x>=15 then DragDir:=0;  // User wants to drag horizontally
      if pt.y>=15 then DragDir:=1;  // User wants to drag vertically
    end;
    if DragDir=0 then
    begin
      StatusBar1.Panels[2].Text:= 'X = '+IntToStr(pt.x);
      dragData:=pt.x;
    end;

    if DragDir=1 then
    begin
      StatusBar1.Panels[2].Text:= 'Y = '+IntToStr(pt.y);
      dragData:=pt.y;
    end;
    Image1.Repaint;
  end;
end;

procedure TForm1.Image1Paint(Sender: TObject);
var
  n : Integer;
  aspect:LongInt;
begin
  if RulersVisible and (Image1.Picture.Graphic<>nil) then
  begin
    if Length(rulertypes)>0 then
    begin
      Image1.Canvas.Pen.Color:=clGreen;
      for n:=0 to Length(rulertypes)-1 do
      begin
        aspect:= rulers[n]*Image1.Width div Image1.Picture.Width;
        if rulertypes[n]=0 then
        begin
          Image1.Canvas.MoveTo(aspect,0);
          Image1.Canvas.LineTo(aspect,Image1.Canvas.Height);
        end;
        if rulertypes[n]=1 then
        begin
          Image1.Canvas.MoveTo(0,aspect);
          Image1.Canvas.LineTo(Image1.Canvas.Width,aspect);
        end;
      end;
    end;
    if DragDir>-1 then
    begin
      Image1.Canvas.Pen.Color:=clRed;
      if DragDir=0 then
      begin
        Image1.Canvas.MoveTo(DragData,0);
        Image1.Canvas.LineTo(DragData,Image1.Canvas.Height);
      end;
      if DragDir=1 then
      begin
        Image1.Canvas.MoveTo(0,DragData);
        Image1.Canvas.LineTo(Image1.Canvas.Width,DragData);
      end;
    end;
  end;
end;

procedure TForm1.Image1StartDrag(Sender: TObject; var DragObject: TDragObject);
begin

end;

procedure TForm1.MenuItem2Click(Sender: TObject);
var
  OldPort: Integer;
begin
  FormSettings.PutSettings(settings);
  if FormSettings.ShowModal = mrOK then
  begin
    OldPort := FSocket.Port;
    FormSettings.GetSettings(settings);
    StatusBar1.Panels[1].Text := IntToStr(settings.rotation);
    StatusBar1.Panels[3].Text := FSettingsManager.GetLANIp + ':' + IntToStr(settings.tcpport);
    FSettingsManager.Save(settings);
    if zpldatalen > 0 then RenderAndDisplay;
    if OldPort <> settings.tcpport then
    begin
      FreeSocket;
      InitSocket;
    end;
  end;
end;

procedure TForm1.MenuItem3Click(Sender: TObject);
begin
  Form1.Close;
end;

procedure TForm1.MSourceCodeChange(Sender: TObject);
begin
  TBLock.Checked:=(MSourceCode.Lines.Count > 3);
end;

procedure TForm1.Panel2Click(Sender: TObject);
begin
  if Panel1.Width<50 then begin
    Form1.Width:=Form1.Width + Form1.Width;
    Panel1.Width:=Panel1.Width + (Form1.Width div 2);
  end
  else begin
    Form1.Width:=Form1.Width div 2;
    Panel1.Width:=15;
  end
end;

procedure TForm1.Shape1EndDrag(Sender, Target: TObject; X, Y: Integer);
begin
  DragDir:=-1;
  Image1.Repaint;
end;

procedure TForm1.Shape1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and (Image1.Picture.Graphic<>nil) then
  begin
    Shape1.BeginDrag(False);
    if not RulersVisible then
    begin
      RulersVisible:=true;
      Image1.Repaint;
    end;
  end;
  if Button = mbRight then
  begin
    SetLength(rulers,0);
    SetLength(rulertypes,0);
    Image1.Repaint;
  end;
end;

procedure TForm1.Shape1MouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and (X<Shape1.Width) and (Y<Shape1.Height) then
  begin
    RulersVisible:=False;
    Image1.Repaint;
    //StatusBar1.Panels[2].Text:= 'Tilt';
  end;
end;

procedure TForm1.Shape1StartDrag(Sender: TObject; var DragObject: TDragObject);
begin
  DragDir:=-1;
  RulersVisible:=True;
end;

procedure TForm1.StatusBar1Click(Sender: TObject);
begin
  with settings do begin
    rotation := rotation + 90;
    if rotation > 270 then rotation := 0;
    StatusBar1.Panels[1].Text := IntToStr(rotation);
  end;
  if zpldatalen > 0 then RenderAndDisplay;
end;

procedure TForm1.TBLockChange(Sender: TObject);
begin

end;

procedure TForm1.AcceptTimerTimer(Sender: TObject);
begin
  FSocket.StartAccepting;
end;

procedure TForm1.BRenderManualClick(Sender: TObject);
begin
  if MSourceCode.Lines.Count > 3 then begin
    zpldatalen := MSourceCode.Lines.Text.Length;
    Move(MSourceCode.Lines.Text[1], zpldata^, zpldatalen);
    RenderAndDisplay;
  end;
end;

procedure TForm1.NothingHappened(Sender: TObject);
begin
  FSocket.StopAccepting;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  FreeSocket;
  FRenderer := nil;
  FreeAndNil(FFileService);
  FreeAndNil(FPrintService);
  FreeAndNil(FSettingsManager);
  FreeMem(zpldata, 1000000);
end;

procedure TForm1.RenderAndDisplay;
var
  PngData: TMemoryStream;
begin
  Image1.Picture.Clear;
  Image1.Invalidate;
  Application.ProcessMessages;
  PngData := TMemoryStream.Create;
  try
    if FRenderer.Render(zpldata, zpldatalen, settings, PngData) then
    begin
      Image1.Picture.LoadFromStream(PngData);
      Inc(jobCnt);
      StatusBar1.Panels[0].Text := Format('#%d - %s', [jobCnt, DateTimeToStr(Now)]);
      if settings.save then FFileService.SavePng(Image1.Picture, settings);
      if settings.print then
        try
          FPrintService.Print(zpldata, zpldatalen, Image1.Picture.Graphic, settings);
        except
          on E: Exception do ShowMessage(E.Message);
        end;
    end
    else
      ShowMessage(FRenderer.GetLastError);
  finally
    FreeAndNil(PngData);
  end;
end;

procedure TForm1.ReadJetData(Sender: TObject; DataStream: TSocketStream);
var
  len: LongInt;
  db: string;
begin
  zpldatalen := 0;
  repeat
    len := DataStream.Read((zpldata + zpldatalen)^, 1000000 - zpldatalen);
    if len > 0 then zpldatalen := zpldatalen + len;
  until len <= 0;
  SetString(db, PAnsiChar(zpldata), zpldatalen);
  DebugLn(DateTimeToStr(Now));
  DebugLn(db);
  DataStream.Free;
  if not TBLock.Checked then begin
    MSourceCode.Text := db;
    TBLock.Checked := False;
  end;
  if settings.saverawdata then FFileService.SaveRaw(db, settings);
  RenderAndDisplay;
end;

end.


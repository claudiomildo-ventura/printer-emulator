unit zplview_main;

{$mode objfpc}{$H+}

{
  ZPL Viewer - Main Display Form
  
  Purpose:
    Provides a GUI for visualizing ZPL (Zebra Programming Language) label commands.
    Integrates with Labelary API for rendering and supports live preview with rulers,
    rotation, DPI settings, and direct printing.
  
  Architecture:
    - Socket Server: Listens on TCP port for incoming ZPL data (Jet Direct protocol)
    - Data Pipeline: TCP → TMemoryStream → Labelary API → PNG → Image display
    - Settings: INI-based configuration (DPI, rotation, printer, paths)
    - Rulers: Overlay system for precise label measurements and positioning
  
  Key Features:
    • Real-time ZPL rendering via Labelary cloud API
    • Manual ZPL code input and rendering
    • Ruler overlay (vertical/horizontal) with drag-and-position
    • 90° rotation cycling (0°, 90°, 180°, 270°)
    • Direct printer output (raw ZPL or rasterized image)
    • PNG save capability with timestamp
    • TCP/IP socket server for network printing devices
}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ExtCtrls,
  StdCtrls, ComCtrls, Sockets, ssockets,fphttpclient,zplview_settings,dateutils,
  INIFiles,Printers,lazlogger,DefaultTranslator;

const
  { Data and Network Constants }
  MAX_ZPL_SIZE = 1000000;        // 1MB maximum ZPL data size
  DEFAULT_TCP_PORT = 9100;       // Standard ZPL/Jet Direct port
  DEFAULT_DPI = 203;             // Default label DPI (8dpmm)
  
  { UI Constants }
  RULER_PANEL_WIDTH = 15;        // Width of left ruler panel (pixels)
  RULER_DRAG_THRESHOLD = 50;     // Panel size threshold for collapse/expand
  SOCKET_ACCEPT_TIMEOUT = 100;   // Socket idle timeout (ms)

type

  { TForm1 - ZPL Label Viewer and Renderer
    
    Main application form providing real-time ZPL rendering, measurement tools,
    and printer integration. Manages socket server for network printing devices
    and provides UI for settings/rotation/ruler placement.
  }
  TForm1 = class(TForm)
    { UI Components }
    BRenderManual: TButton;       // Manual render button for pasted ZPL code
    Image1: TImage;               // Main label preview canvas
    MainMenu1: TMainMenu;         // Application menu bar
    MSourceCode: TMemo;           // ZPL source code editor
    MenuItem1: TMenuItem;         // File menu
    MenuItem2: TMenuItem;         // Settings menu
    MenuItem3: TMenuItem;         // Exit menu
    AcceptTimer: TTimer;          // Socket accept polling timer
    Panel1: TPanel;               // Left ruler panel
    Panel2: TPanel;               // Splitter between ruler panel and image
    Shape1: TShape;               // Draggable ruler origin
    StatusBar1: TStatusBar;       // Status display bar
    TBLock: TToggleBox;           // Lock toggle for source code
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
  private
    { Network }
    socket : TINetServer;         // TCP server listening for ZPL data
    
    { Data }
    zpldata : TMemoryStream;      // Current ZPL command buffer (max 1MB)
    
    { Ruler/Measurement }
    dragDir: Integer;             // Current drag direction: -1=none, 0=horizontal, 1=vertical
    dragData: Integer;            // Current drag position in pixels
    rulers:     array of integer; // Ruler positions in image coordinates
    rulertypes: array of integer; // Ruler types: 0=Vertical, 1=Horizontal
    RulersVisible : Boolean;      // Show/hide ruler overlay
    
    { Settings and State }
    settings : ZViewSettings;     // Application settings (DPI, rotation, printer, etc.)
    jobCnt: Integer;              // Total rendered jobs counter
    inifile  : string;            // Path to configuration INI file
    
    { Socket Event Handlers }
    procedure ReadJetData(Sender: TObject; DataStream: TSocketStream);
    
    { Rendering and HTTP }
    procedure GetLabelaryData;    // Render ZPL via Labelary API
    
    { Socket Management }
    procedure NothingHappened(Sender: TObject);
    procedure CreateAndBindSocket; // Initialize socket with current settings
    
    { Settings I/O }
    procedure LoadSettings;       // Load configuration from INI file
    procedure SaveSettings;       // Save configuration to INI file
    procedure ResetSettings;      // Reset to default values
    
    { Utility }
    function  IniFileName():string;  // Get platform-specific INI path
    function  GetLANIp():string;     // Get local IP address
    
    { Output }
    procedure RePrint;            // Send to printer (raw or image)
    procedure SavePng;            // Save rendered PNG with timestamp
    procedure SaveRaw(data:string); // Save raw ZPL to text file
  public

  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 Implementation }

{ === INITIALIZATION AND CLEANUP === }

function TForm1.GetLANIp():string;
(* Retrieve the local LAN IP address by creating a socket connection to Cloudflare DNS.
   This determines which network interface the device will listen on.
   Returns: Local IP address string (e.g., '192.168.1.100') *)
var
  s: TInetSocket;
begin
  try
    s := TInetSocket.Create('1.1.1.1',80);
    GetLANIp:=NetAddrToStr(s.LocalAddress.sin_addr);
  finally
    s.Free;
  end;
end;

function  TForm1.IniFileName():string;
(* Determine the platform-specific path for the application configuration file.
   - Windows: Uses APPDATA environment variable
   - Linux/Mac: Uses HOME/.config/ directory
   
   Returns: Full path to .ini file *)
var f,i:string;
begin
  i:=ChangeFileExt(ExtractFileName(Application.ExeName),'.ini');
  if GetEnvironmentVariable('APPDATA')<>'' then
    IniFileName:=GetEnvironmentVariable('APPDATA')+'\'+i
  else if GetEnvironmentVariable('HOME')<>'' then
    IniFileName:=GetEnvironmentVariable('HOME')+'/.config/'+i
  else
    IniFileName:=i;
end;

procedure TForm1.FormCreate(Sender: TObject);
(* Application initialization:
   1. Create ZPL data buffer
   2. Load configuration from INI file
   3. Display IP and port on status bar
   4. Initialize socket server for network printing
   5. Initialize ruler system *)
begin
  zpldata := TMemoryStream.Create;
  jobCnt := 0;

  inifile := IniFileName();
  ResetSettings;
  LoadSettings;
  StatusBar1.Panels[3].Text := GetLANIp() + ':' + IntToStr(settings.tcpport);

  CreateAndBindSocket;

  SetLength(rulers, 0);
  SetLength(rulertypes, 0);
  DragDir := -1;
  RulersVisible := True;
  Panel1.Width := RULER_PANEL_WIDTH;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
(* Application cleanup: Free socket and ZPL data buffer *)
begin
  socket.Free;
  zpldata.Free;
end;


{ === RULER SYSTEM (Measurement and Positioning) === }

procedure TForm1.Image1DragDrop(Sender, Source: TObject; X, Y: Integer);
(* Place a ruler when user drops the Shape1 control on the image.
   Converts screen coordinates to image coordinates using aspect ratio.
   
   Parameters:
   - Source: Should be Shape1 (the draggable ruler origin)
   - X, Y: Drop position in screen coordinates
   
   Logic: Stores ruler position and type (0=H, 1=V) in respective arrays *)
var
  aspect: LongInt;
begin
  if ((Source = Shape1) and (DragDir>-1) and (Image1.Picture.Graphic<>nil) ) then
  begin
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
(* Handle shape dragging over image to determine ruler direction and position.
   
   Direction determination (first movement):
   - If cursor X > RULER_PANEL_WIDTH: Horizontal ruler (0)
   - If cursor Y > RULER_PANEL_WIDTH: Vertical ruler (1)
   
   Updates status bar with real-time position feedback *)
var
  pt : tPoint;
begin
  if (Source = Shape1) then
  begin
    Accept := True;
    RulersVisible := True;
    pt := ScreenToClient(Mouse.CursorPos);
    if DragDir = -1 then
    begin
      if pt.x >= RULER_PANEL_WIDTH then DragDir := 0;
      if pt.y >= RULER_PANEL_WIDTH then DragDir := 1;
    end;
    if DragDir = 0 then
    begin
      StatusBar1.Panels[2].Text := 'X = ' + IntToStr(pt.x);
      dragData := pt.x;
    end;

    if DragDir = 1 then
    begin
      StatusBar1.Panels[2].Text := 'Y = ' + IntToStr(pt.y);
      dragData := pt.y;
    end;
    Image1.Repaint;
  end;
end;

procedure TForm1.Image1Paint(Sender: TObject);
(* Render visual overlay on image canvas:
   1. Green lines for placed rulers (scaled to current zoom level)
   2. Red line for current drag position (preview)
   
   Formula: aspect = ruler_pixels * Image1.Width / Image1.Picture.Width
   This scales image-space coordinates to screen-space *)
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

procedure TForm1.Shape1StartDrag(Sender: TObject; var DragObject: TDragObject);
(* Initialize ruler drag gesture: Reset direction and show rulers *)
begin
  DragDir:=-1;
  RulersVisible:=True;
end;

procedure TForm1.Shape1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
(* Handle Shape1 mouse events:
   - Left click: Begin drag to create new ruler
   - Right click: Clear all rulers *)
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
(* Hide rulers when drag ends *)
begin
  if (Button = mbLeft) and (X<Shape1.Width) and (Y<Shape1.Height) then
  begin
    RulersVisible:=False;
    Image1.Repaint;
  end;
end;

procedure TForm1.Shape1EndDrag(Sender, Target: TObject; X, Y: Integer);
(* Finalize ruler drag: Reset direction *)
begin
  DragDir:=-1;
  Image1.Repaint;
end;


{ === UI EVENTS (Menu, Buttons, Settings) === }

procedure TForm1.MenuItem2Click(Sender: TObject);
(* Settings dialog handler:
   1. Open settings form (rotation, DPI, printer, paths)
   2. If OK: Save settings and restart socket if port changed
   3. If socket port changed: Free old socket and recreate *)
begin
  FormSettings.PutSettings(settings);
  if FormSettings.ShowModal = mrOK then
  begin
    FormSettings.GetSettings(settings);
    StatusBar1.Panels[1].Text := IntToStr(settings.rotation);
    StatusBar1.Panels[3].Text := GetLANIp() + ':' + IntToStr(settings.tcpport);
    SaveSettings;
    if zpldata.Size > 0 then GetLabelaryData;
    if socket.Port <> settings.tcpport then
    begin
      socket.Free;
      CreateAndBindSocket;
    end;
  end;
end;

procedure TForm1.MenuItem3Click(Sender: TObject);
(* Exit application *)
begin
  Form1.Close;
end;

procedure TForm1.MSourceCodeChange(Sender: TObject);
(* Auto-lock source code when content is sufficient for rendering *)
begin
  TBLock.Checked:=(MSourceCode.Lines.Count > 3);
end;

procedure TForm1.Panel2Click(Sender: TObject);
(* Toggle ruler panel size by clicking splitter.
   Expands or collapses left panel *)
begin
  if Panel1.Width < RULER_DRAG_THRESHOLD then begin
    Form1.Width := Form1.Width + Form1.Width;
    Panel1.Width := Panel1.Width + (Form1.Width div 2);
  end
  else begin
    Form1.Width := Form1.Width div 2;
    Panel1.Width := RULER_PANEL_WIDTH;
  end
end;

procedure TForm1.StatusBar1Click(Sender: TObject);
(* Rotate label 90° clockwise on status bar click.
   Cycles: 0° → 90° → 180° → 270° → 0° *)
begin
  with settings do begin
    rotation := rotation + 90;
    if rotation > 270 then rotation := 0;
    StatusBar1.Panels[1].Text := IntToStr(rotation);
  end;
  if zpldata.Size > 0 then GetLabelaryData;
end;

procedure TForm1.BRenderManualClick(Sender: TObject);
(* Manual render button: Render ZPL code from source editor.
   Checks minimum line count before processing *)
var
  Code: string;
begin
  if MSourceCode.Lines.Count > 3 then begin
    Code := MSourceCode.Lines.Text;
    zpldata.Clear;
    zpldata.Write(Code[1], Length(Code));
    zpldata.Position := 0;
    GetLabelaryData;
  end;
end;

procedure TForm1.CreateAndBindSocket;
begin
  if socket <> nil then
    socket.Free;
  
  try
    socket := TINetServer.Create(settings.bindadr, settings.tcpport);
    socket.ReuseAddress := true;
    socket.MaxConnections := 1;
    socket.OnConnect := @ReadJetData;
    socket.OnIdle := @NothingHappened;
    socket.Bind;
    socket.Listen;
    socket.AcceptIdleTimeOut := SOCKET_ACCEPT_TIMEOUT;
  except
    on E: Exception do
    begin
      ShowMessage('Failed to create socket: ' + E.Message);
      socket := nil;
    end;
  end;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  socket.Free;
  zpldata.Free;
end;

procedure TForm1.SavePng;
(* Save rendered label image to PNG file with Unix timestamp filename.
   Respects configured savepath setting *)
var
  filename:string;
begin
  filename:=settings.savepath;
  if filename<>'' then filename:=filename+'/';
  filename:=Format('%s%d.png',[SetDirSeparators(filename),DateTimeToUnix(now)]);
  Image1.Picture.SaveToFile(filename);
end;

procedure TForm1.SaveRaw(data:string);
(* Save raw ZPL source code to text file (rawdata.txt).
   Appends to file to maintain history *)
Var
 File1:TextFile;
 filename:string;
begin
  filename:=settings.savepath;
  if filename<>'' then filename:=filename+'/';
  filename:=Format('%srawdata.txt',[SetDirSeparators(filename)]);
  AssignFile(File1,filename);
  Try
    Rewrite(File1);
    Writeln(File1,data);
  Finally
    CloseFile(File1);
  end;
end;


procedure TForm1.RePrint;
(* Send label to configured printer.
   Two modes:
   1. Raw mode: Send ZPL directly to printer (requires network printer)
   2. Image mode: Print rendered PNG image at configured DPI *)
var
  p: integer;
  written: Integer;
begin
  p := Printer.Printers.IndexOf(settings.printer);
  if p < 0 then
  begin
    ShowMessage('Eingesteller Drucker ungültig');
    exit;
  end;
  
  if zpldata.Size = 0 then
  begin
    ShowMessage('Es gibts nichts zu drucken!');
    exit;
  end;
  
  Printer.PrinterIndex := p;
  if Printer.Printing then Printer.Abort;
  try
    Printer.Title := 'ZPL-View reprint';
    Printer.RawMode := settings.printraw;
    Printer.BeginDoc;
    if settings.printraw then
    begin
      zpldata.Position := 0;
      Printer.Write(zpldata.Memory^, zpldata.Size, written);
    end
    else
      printer.Canvas.StretchDraw(Classes.Rect(0, 0,
        Image1.Picture.Graphic.Width * printer.XDPI div settings.resolution,
        Image1.Picture.Graphic.Height * printer.YDPI div settings.resolution),
        Image1.Picture.Graphic);
  finally
    Printer.EndDoc;
  end;
end;

procedure TForm1.GetLabelaryData;
(* Core rendering function: Send ZPL to Labelary cloud API and display result.
   
   Flow:
   1. Validate ZPL data exists
   2. POST ZPL + rotation to: api.labelary.com/v1/printers/{dpi}/labels/{width}x{height}/0/
   3. DPI mapping: 152→6dpmm, 203→8dpmm, 300→12dpmm, 600→24dpmm
   4. Parse PNG response and display in Image1
   5. Auto-save PNG if configured
   6. Auto-print if configured
   
   Labelary API: https://www.labelary.com/service.html *)
var FPHTTPClient: TFPHTTPClient;
    Fmt,URL,dpi: String;
    FmtSet:TFormatSettings;
    PngData: TMemoryStream;
    errormsg:string;
begin
  Image1.Picture.Clear;
  Image1.Invalidate;
  Application.ProcessMessages;
  
  if zpldata.Size = 0 then
  begin
    DebugLn('No ZPL data to render');
    Exit;
  end;
  
  FPHTTPClient := TFPHTTPClient.Create(nil);
  PngData := TMemoryStream.Create;
  try
    FPHTTPClient.AllowRedirect := True;
    zpldata.Position := 0;
    FPHTTPClient.RequestBody := zpldata;
    FPHTTPClient.AddHeader('X-Rotation', IntToStr(settings.rotation));
    try
      case settings.resolution of
        152: dpi := '6dpmm';
        203: dpi := '8dpmm';
        300: dpi := '12dpmm';
        600: dpi := '24dpmm';
      else
        dpi := '8dpmm';
      end;
      FmtSet := DefaultFormatSettings;
      FmtSet.DecimalSeparator := '.';
      Fmt := 'http://api.labelary.com/v1/printers/%s/labels/%nx%n/0/';
      URL := Format(Fmt, [dpi, settings.width, settings.height], FmtSet);
      FPHTTPClient.Post(URL, PngData);
      PngData.Position := 0;
      if FPHTTPClient.ResponseStatusCode = 200 then
      begin
        Image1.Picture.LoadFromStream(PngData);
        Inc(jobCnt);
        StatusBar1.Panels[0].Text := format('#%d - %s', [jobCnt, DateTimeToStr(Now)]);
        if settings.save then
          SavePng;
        if settings.print then
          RePrint;
      end
      else
      begin
        if PngData.Size < 100 then
        begin
          SetString(errormsg, PAnsiChar(PngData.Memory), PngData.Size);
        end
        else
          ShowMessage('Labelary Error:' + FPHTTPClient.ResponseStatusText)
      end;
    except
      on E: exception do
        ShowMessage(E.Message);
    end;
  finally
    FreeAndNil(PngData);
    FreeAndNil(FPHTTPClient);
  end;
end;


{ === SOCKET MANAGEMENT === }

procedure TForm1.AcceptTimerTimer(Sender: TObject);
(* Timer callback: Resume accepting socket connections *)
begin
  socket.StartAccepting;
end;

procedure TForm1.NothingHappened(Sender: TObject);
(* Socket idle callback: Stop accepting to avoid blocking *)
begin
  socket.StopAccepting;
end;

procedure TForm1.CreateAndBindSocket;
(* Initialize TCP socket server:
   1. Create TINetServer on configured IP/port
   2. Set callbacks (OnConnect → ReadJetData, OnIdle → NothingHappened)
   3. Bind and listen
   4. Exception handling with user feedback
   
   Socket will listen for incoming ZPL commands and trigger ReadJetData *)
begin
  if socket <> nil then
    socket.Free;
  
  try
    socket := TINetServer.Create(settings.bindadr, settings.tcpport);
    socket.ReuseAddress := true;
    socket.MaxConnections := 1;
    socket.OnConnect := @ReadJetData;
    socket.OnIdle := @NothingHappened;
    socket.Bind;
    socket.Listen;
    socket.AcceptIdleTimeOut := SOCKET_ACCEPT_TIMEOUT;
  except
    on E: Exception do
    begin
      ShowMessage('Failed to create socket: ' + E.Message);
      socket := nil;
    end;
  end;
end;

procedure TForm1.ReadJetData(Sender: TObject; DataStream: TSocketStream);
(* Socket connection handler: Read incoming ZPL data via Jet Direct protocol.
   
   Process:
   1. Clear previous ZPL buffer
   2. Read data in 4KB chunks (safety: max MAX_ZPL_SIZE)
   3. Convert to string for debug output
   4. Update source editor if not locked
   5. Pass to rendering pipeline
   
   Safety: Bounds-checks prevent buffer overflow *)
var
  Buffer: array[0..4095] of Byte;
  len: LongInt;
  db: string;
begin
  zpldata.Clear;
  zpldata.Position := 0;
  
  try
    repeat
      len := DataStream.Read(Buffer[0], SizeOf(Buffer));
      if len > 0 then
      begin
        if zpldata.Size + len > MAX_ZPL_SIZE then
        begin
          DebugLn('ZPL data exceeds maximum size, truncating');
          len := MAX_ZPL_SIZE - zpldata.Size;
        end;
        if len > 0 then
          zpldata.Write(Buffer[0], len);
      end;
    until len <= 0;
    
    zpldata.Position := 0;
    SetString(db, PAnsiChar(zpldata.Memory), zpldata.Size);
    DebugLn(DateTimeToStr(Now));
    DebugLn(db);
    
    if not TBLock.Checked then
    begin
      MSourceCode.Text := db;
      TBLock.Checked := false;
    end;
    
    if settings.saverawdata then
      SaveRaw(db);
    
    GetLabelaryData;
  finally
    DataStream.Free;
  end;
end;

{ === SETTINGS MANAGEMENT (INI Serialization) === }

procedure TForm1.LoadSettings;
(* Load application settings from INI file.
   Settings stored per-key in [SETTINGS] section.
   Provides sensible defaults if keys not found:
   - resolution: 203 DPI
   - tcpport: 9100 (standard ZPL/Jet Direct)
   - bindadr: 0.0.0.0 (listen on all interfaces)
   - label size: 4"x3" *)
var
  INI: TINIFile;
begin
  INI := TINIFile.Create(inifile);
  with settings do begin
    resolution := INI.ReadInteger('SETTINGS','resolution',DEFAULT_DPI);
    rotation := INI.ReadInteger('SETTINGS','rotation',0);
    width := INI.ReadFloat('SETTINGS','width',4.0);
    height := INI.ReadFloat('SETTINGS','height',3.0);
    save := INI.ReadBool('SETTINGS','save',false);
    savepath := INI.ReadString('SETTINGS','savepath','');
    print := INI.ReadBool('SETTINGS','print',false);
    printraw := INI.ReadBool('SETTINGS','printraw',false);
    printer := INI.ReadString('SETTINGS','printer','');
    executescript := INI.ReadBool('SETTINGS','executescript',false);
    saverawdata := INI.ReadBool('SETTINGS','saverawdata',false);
    scriptpath := INI.ReadString('SETTINGS','scriptpath','');
    tcpport := INI.ReadInteger('SETTINGS','tcpport',DEFAULT_TCP_PORT);
    bindadr := INI.ReadString('SETTINGS','bindadr','0.0.0.0');
  end;
  INI.Free;
end;

procedure TForm1.SaveSettings;
(* Persist current settings to INI file.
   All ZViewSettings fields are written to [SETTINGS] section.
   Overwrites existing file on save. *)
var
  INI: TINIFile;
begin
  INI := TINIFile.Create(inifile);
  with settings do begin
    INI.WriteInteger('SETTINGS','resolution',resolution);
    INI.WriteInteger('SETTINGS','rotation',rotation);
    INI.WriteFloat('SETTINGS','width',width);
    INI.WriteFloat('SETTINGS','height',height);
    INI.WriteBool('SETTINGS','save',save);
    INI.WriteString('SETTINGS','savepath',savepath);
    INI.WriteBool('SETTINGS','print',print);
    INI.WriteBool('SETTINGS','printraw',printraw);
    INI.WriteString('SETTINGS','printer',printer);
    INI.WriteBool('SETTINGS','executescript',executescript);
    INI.WriteBool('SETTINGS','saverawdata',saverawdata);
    INI.WriteString('SETTINGS','scriptpath',scriptpath);
    INI.WriteInteger('SETTINGS','tcpport',tcpport);
    INI.WriteString('SETTINGS','bindadr',bindadr);
  end;
  INI.Free;
end;

procedure TForm1.ResetSettings;
(* Reset all settings to factory defaults:
   - 203 DPI (8dpmm - standard label printer)
   - No rotation (0°)
   - 4" x 3" label size
   - No auto save/print
   - TCP port 9100 (Jet Direct/AppSocket)
   - Listen on all interfaces (0.0.0.0)
   
   Called on first startup if INI file doesn't exist *)
begin
  with settings do begin
    resolution := DEFAULT_DPI;
    rotation := 0;
    width := 4.0;
    height := 3.0;
    save := false;
    savepath := '';
    print := false;
    printraw := false;
    printer := '';
    executescript := false;
    saverawdata := false;
    scriptpath := '';
    tcpport := DEFAULT_TCP_PORT;
    bindadr := '0.0.0.0';
  end;
end;

end.


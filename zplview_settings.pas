unit zplview_settings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Buttons, StdCtrls,
  Printers, ExtCtrls;

type
  ZViewSettings = record
    resolution: integer;
    rotation: integer;
    Width, Height: real;
    save: boolean;
    savepath: string;
    print: boolean;
    printraw: boolean;
    printer: string;
    executescript: boolean;
    scriptpath: string;
    tcpport: integer;
    bindadr: string;
    saverawdata: boolean;
  end;

  { TFrmPrintEmulatorSettings }

  TFrmPrintEmulatorSettings = class(TForm)
    BitBtn1: TBitBtn;
    BitBtn2: TBitBtn;
    Button1: TButton;
    ChbSave: TCheckBox;
    ChbPrint: TCheckBox;
    ChbRaw: TCheckBox;
    ChbScript: TCheckBox;
    ChbSaveRaw: TCheckBox;
    ComPrinter: TComboBox;
    ComRes: TComboBox;
    ComRotate: TComboBox;
    Edit1: TEdit;
    EdtScript: TEdit;
    EdtPort: TEdit;
    EdtPath: TEdit;
    EdtHeight: TEdit;
    EdtBind: TEdit;
    EdtWidth: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    RGEngine: TRadioGroup;
    procedure FormShow(Sender: TObject);
  public
    procedure PutSettings(var setup: ZViewSettings);
    procedure GetSettings(var setup: ZViewSettings);
  end;

var
  FrmPrintEmulatorSettings: TFrmPrintEmulatorSettings;

procedure NormalizeSettings(var setup: ZViewSettings);

implementation

{$R *.lfm}

{ TFrmPrintEmulatorSettings }

function RotationToComboIndex(Rotation: integer): integer;
begin
  case Rotation of
    0: Result := 0;
    90: Result := 1;
    180: Result := 2;
    270: Result := 3;
  else
    Result := 0;
  end;
end;

function ComboIndexToRotation(Index: integer): integer;
begin
  case Index of
    1: Result := 90;
    2: Result := 180;
    3: Result := 270;
  else
    Result := 0;
  end;
end;

function IsSupportedResolution(Resolution: integer): boolean;
begin
  Result := (Resolution = 152) or (Resolution = 203) or
    (Resolution = 300) or (Resolution = 600);
end;

function IsSupportedRotation(Rotation: integer): boolean;
begin
  Result := (Rotation = 0) or (Rotation = 90) or
    (Rotation = 180) or (Rotation = 270);
end;

procedure NormalizeSettings(var setup: ZViewSettings);
begin
  if not IsSupportedResolution(setup.resolution) then
    setup.resolution := 203;

  if not IsSupportedRotation(setup.rotation) then
    setup.rotation := 0;

  if setup.Width <= 0 then
    setup.Width := 4.0;

  if setup.Height <= 0 then
    setup.Height := 3.0;

  if (setup.tcpport < 1) or (setup.tcpport > 65535) then
    setup.tcpport := 9100;

  if Trim(setup.bindadr) = '' then
    setup.bindadr := '0.0.0.0';
end;

procedure TFrmPrintEmulatorSettings.FormShow(Sender: TObject);
begin
  ComPrinter.Items.Assign(Printer.Printers);
end;

procedure TFrmPrintEmulatorSettings.PutSettings(var setup: ZViewSettings);
var
  idx: Integer;
begin
  ComPrinter.Items.Assign(Printer.Printers);

  ComRes.Text := IntToStr(setup.resolution);
  ComRotate.ItemIndex := RotationToComboIndex(setup.rotation);
  EdtWidth.Text := FloatToStr(setup.Width);
  EdtHeight.Text := FloatToStr(setup.Height);

  ChbSave.Checked := setup.save;
  EdtPath.Text := setup.savepath;

  ChbPrint.Checked := setup.print;
  ChbRaw.Checked := setup.printraw;

  idx := ComPrinter.Items.IndexOf(setup.printer);
  
  if idx >= 0 then
    ComPrinter.ItemIndex := idx
  else
    ComPrinter.ItemIndex := -1;

  ChbScript.Checked := setup.executescript;
  ChbSaveRaw.Checked := setup.saverawdata;

  EdtScript.Text := setup.scriptpath;
  EdtPort.Text := IntToStr(setup.tcpport);
  EdtBind.Text := setup.bindadr;
end;

procedure TFrmPrintEmulatorSettings.GetSettings(var setup: ZViewSettings);
begin
  setup.resolution := StrToIntDef(ComRes.Text, 0);
  setup.rotation := ComboIndexToRotation(ComRotate.ItemIndex);

  setup.Width := StrToFloatDef(EdtWidth.Text, 0);
  setup.Height := StrToFloatDef(EdtHeight.Text, 0);

  setup.save := ChbSave.Checked;
  setup.savepath := EdtPath.Text;

  setup.print := ChbPrint.Checked;
  setup.printraw := ChbRaw.Checked;
  setup.printer := ComPrinter.Text;

  setup.executescript := ChbScript.Checked;
  setup.saverawdata := ChbSaveRaw.Checked;

  setup.scriptpath := EdtScript.Text;
  setup.tcpport := StrToIntDef(EdtPort.Text, 0);
  setup.bindadr := EdtBind.Text;

  NormalizeSettings(setup);
end;

end.

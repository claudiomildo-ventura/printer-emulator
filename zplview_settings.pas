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

  { TFormSettings }

  TFormSettings = class(TForm)
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
  FormSettings: TFormSettings;

implementation

{$R *.lfm}

{ TFormSettings }

procedure TFormSettings.FormShow(Sender: TObject);
begin
  ComPrinter.Items.Assign(Printer.Printers);
end;

procedure TFormSettings.PutSettings(var setup: ZViewSettings);
var
  idx: Integer;
begin
  ComPrinter.Items.Assign(Printer.Printers);

  ComRes.Text := IntToStr(setup.resolution);
  ComRotate.Text := IntToStr(setup.rotation);
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

procedure TFormSettings.GetSettings(var setup: ZViewSettings);
begin
  setup.resolution := StrToIntDef(ComRes.Text, 0);
  setup.rotation := StrToIntDef(ComRotate.Text, 0);

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
end;

end.

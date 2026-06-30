unit zplview_print_service;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Printers, zplview_settings;

type
  TZplPrintService = class
  public
    procedure Print(ZplData: Pointer; ZplLen: Integer;
                    Image: TGraphic; const Settings: ZViewSettings);
  end;

implementation

procedure TZplPrintService.Print(ZplData: Pointer; ZplLen: Integer;
  Image: TGraphic; const Settings: ZViewSettings);
var
  PrinterIdx: Integer;
  Written: Integer;
begin
  PrinterIdx := Printer.Printers.IndexOf(Settings.printer);
  if PrinterIdx < 0 then
    raise Exception.Create('Eingesteller Drucker ungültig');
  if ZplLen = 0 then
    raise Exception.Create('Es gibts nichts zu drucken!');

  Printer.PrinterIndex := PrinterIdx;
  if Printer.Printing then Printer.Abort;
  try
    Printer.Title := 'ZPL-View reprint';
    Printer.RawMode := Settings.printraw;
    Printer.BeginDoc;
    if Settings.printraw then
      Printer.Write(ZplData^, ZplLen, Written)
    else
      Printer.Canvas.StretchDraw(
        Classes.Rect(0, 0,
          Image.Width * Printer.XDPI div Settings.resolution,
          Image.Height * Printer.YDPI div Settings.resolution),
        Image);
  finally
    Printer.EndDoc;
  end;
end;

end.

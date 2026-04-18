program zplview;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, zplview_main, zplview_settings, printer4lazarus;

{$R *.res}

begin
  RequireDerivedFormResource:=True;
  Application.Scaled:=True;
  Application.Initialize;
  Application.CreateForm(TFrmPrintEmulator, FrmPrintEmulator);
  Application.CreateForm(TFrmPrintEmulatorSettings, FrmPrintEmulatorSettings);
  Application.Run;
end.


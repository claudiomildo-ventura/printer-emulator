# ZPL-View — Project Overview Prompt

## Context
You are working on **ZPL-View**, a Zebra ZPL printer emulator built with **Free Pascal / Lazarus (LCL)**. 
The application listens on a TCP port (default 9100, Jet-Direct protocol), receives raw ZPL data from any application, 
renders it as a PNG via the **Labelary REST API**, and displays the result in real time.

## Project Structure

```
zplview.lpr                  — Entry point; creates Form1 and FormSettings
zplview_main.pas/.lfm        — Main window (UI coordinator)
zplview_settings.pas/.lfm    — Settings dialog + ZViewSettings record type
zplview_renderer.pas         — IZplRenderer interface + TLabelaryRenderer (HTTP rendering)
zplview_settings_manager.pas — INI persistence, default values, LAN IP detection
zplview_file_service.pas     — PNG export and raw ZPL file save
zplview_print_service.pas    — Physical printer integration (raw ZPL or GDI image)
po/                          — Gettext localization (German base, English/French partial)
```

## Key Types

```pascal
// Defined in zplview_settings.pas
ZViewSettings = record
  resolution: integer;    // 152 | 203 | 300 | 600 DPI
  rotation: integer;      // 0 | 90 | 180 | 270 degrees
  width, height: real;    // Label size in inches (e.g. 4.0 x 3.0)
  save: boolean;          // Auto-save rendered PNG
  savepath: string;       // Output directory
  print: boolean;         // Auto-print on receive
  printraw: boolean;      // Raw ZPL vs rendered image to printer
  printer: string;        // Target printer name
  executescript: boolean; // (reserved, not implemented)
  scriptpath: string;     // (reserved, not implemented)
  tcpport: integer;       // TCP listen port (default 9100)
  bindadr: string;        // Bind address (default 0.0.0.0)
  saverawdata: boolean;   // Append raw ZPL to rawdata.txt
end;

// Defined in zplview_renderer.pas
IZplRenderer = interface
  function Render(ZplData: Pointer; ZplLen: Integer;
                  const Settings: ZViewSettings;
                  Output: TMemoryStream): Boolean;
  function GetLastError: string;
end;
```

## Architecture (SOLID)

| Class | Responsibility |
|---|---|
| `TForm1` | UI events, socket lifecycle, ruler interaction |
| `TZplSettingsManager` | INI load/save/defaults, LAN IP detection |
| `TLabelaryRenderer` | HTTP POST to Labelary API, DPI→dpmm conversion, URL building |
| `TZplFileService` | Save PNG (Unix-timestamp filename) and raw ZPL text |
| `TZplPrintService` | Send to physical printer (raw ZPL or GDI stretched image) |

## Rendering Pipeline

```
TCP:9100 (Jet-Direct)
  → TForm1.ReadJetData           — reads socket into 1 MB buffer (zpldata)
  → TForm1.RenderAndDisplay      — orchestrates render + UI update
  → IZplRenderer.Render          — POST to api.labelary.com, returns PNG stream
  → Image1.Picture.LoadFromStream — displays result
  → TZplFileService.SavePng      — (if settings.save)
  → TZplPrintService.Print       — (if settings.print)
```

## Labelary API

- Base URL: `http://api.labelary.com/v1/printers/{dpmm}/labels/{width}x{height}/0/`
- DPI mapping: 152→6dpmm, 203→8dpmm, 300→12dpmm, 600→24dpmm
- Rotation header: `X-Rotation: 0|90|180|270`
- Method: HTTP POST with raw ZPL body
- Response: PNG image (status 200) or error text

## Settings Persistence

- Windows: `%APPDATA%\zplview.ini`
- Linux: `~/.config/zplview.ini`
- Section: `[SETTINGS]`, keys match `ZViewSettings` field names

## UI Behaviour Notes

- **Sidebar** (Panel1): collapsible ZPL source editor + manual render button
- **Rulers**: drag Shape1 to place horizontal/vertical guides on the image; right-click to clear
- **Rotation**: click StatusBar panel[1] to cycle 0→90→180→270
- **TBLock** toggle: prevents incoming network data from overwriting the ZPL editor
- **Panel[0]**: job counter + timestamp; **Panel[3]**: bound IP:port

## Build

- IDE: Lazarus 2.x / FPC 3.2+
- Required packages: `Printer4Lazarus`, `LCL`
- Target: Windows (GraphicApplication); Linux possible with minor changes
- Build modes: Default, Debug (heap trace + range checks), Release (O3 + smart link)

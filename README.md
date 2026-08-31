# Printer Emulator / ZPL View

Desktop ZPL viewer and printer emulator built with Lazarus/Free Pascal.

The application listens for Zebra-compatible print jobs, renders ZPL labels through the Labelary API, shows the generated label image, and can optionally save or reprint the job.

## Features

- Receive ZPL jobs over TCP, default port `9100`.
- Render labels using Labelary Cloud.
- Manually paste/edit ZPL and render from the UI.
- Validate basic ZPL structure before rendering (`^XA` and `^XZ`).
- Rotate labels by `0`, `90`, `180`, or `270` degrees.
- Configure resolution: `152`, `203`, `300`, or `600` DPI.
- Save rendered labels as PNG files.
- Save raw ZPL data to `rawdata.txt`.
- Reprint rendered images or raw ZPL to a configured printer.
- Keep an in-memory history of the latest rendered jobs.
- Cache rendered labels to avoid repeated API calls for the same ZPL/settings.

## Requirements

- Lazarus IDE / Free Pascal Compiler.
- LCL package.
- `Printer4Lazarus` package.
- `TurboPowerIPro` package.
- Network access to `api.labelary.com` when using the default cloud renderer.

The project file is [zplview.lpi](zplview.lpi).

## Build

Open [zplview.lpi](zplview.lpi) in Lazarus and build the project from the IDE.

If `lazbuild` is available in your `PATH`, you can also build from a terminal:

```powershell
lazbuild zplview.lpi
```

Build output is configured under `lib/$(TargetCPU)-$(TargetOS)`.

## Usage

1. Start the application.
2. Send a ZPL job to the configured TCP address and port, usually port `9100`.
3. The label is rendered in the main window.
4. Use the settings dialog to adjust size, DPI, rotation, save path, printer, TCP port, and bind address.

You can also paste ZPL into the source memo and click `Render`.

Minimal ZPL example:

```zpl
^XA
^FO50,50^A0N,40,40^FDHello ZPL^FS
^XZ
```

## Configuration

Settings are saved to an INI file named after the executable.

On Windows, the file is stored in `%APPDATA%` when available. On Unix-like systems, it is stored under `$HOME/.config` when available. If neither location is available, the current working directory is used.

Invalid or missing values are normalized to safe defaults:

- resolution: `203`
- rotation: `0`
- width: `4.0`
- height: `3.0`
- TCP port: `9100`
- bind address: `0.0.0.0`

## Project Structure

- [zplview.lpr](zplview.lpr): application entry point.
- [zplview_main.pas](zplview_main.pas): main form, UI flow, job history, cache usage, print/save actions.
- [zplview_settings.pas](zplview_settings.pas): settings form and settings validation.
- [zplnet.pas](zplnet.pas): TCP server used to receive ZPL jobs.
- [zplprocessor.pas](zplprocessor.pas): Labelary API integration and ZPL validation.
- [zplrenderthread.pas](zplrenderthread.pas): background render thread.
- [zplcache.pas](zplcache.pas): in-memory render cache.
- [zplstorage.pas](zplstorage.pas): PNG and raw ZPL persistence.
- `po/`: translation files.
- `backup/`: legacy backup copies.

## Notes

- The current implementation renders through Labelary Cloud.
- The Labelary request uses explicit connection and I/O timeouts.
- The UI blocks closing while a render operation is active to avoid callbacks into a destroyed form.
- Script execution and alternate render engines appear in the settings UI as reserved/disabled functionality and are not active in the current code.

## License

MIT. See [LICENSE](LICENSE).

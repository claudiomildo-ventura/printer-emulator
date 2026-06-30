# Copilot / AI Assistant Instructions for ZPL-View

## How to use this file
Paste this block at the start of any AI chat session when asking for help with this project.

---

## Project: ZPL-View

Free Pascal / Lazarus desktop application. Emulates a Zebra thermal printer via TCP (port 9100).
Receives raw ZPL, renders to PNG via Labelary HTTP API, displays + optionally prints/saves.

### Language & conventions
- **Free Pascal**, ObjFPC mode (`{$mode objfpc}{$H+}`)
- Pascal naming: `TMyClass`, `FPrivateField`, `procedure DoSomething`
- Interface prefix: `I` (e.g. `IZplRenderer`)
- `try/finally` for all resource cleanup; `FreeAndNil` over bare `.Free`
- No `Application.ExeName` in non-form units — use `ParamStr(0)` instead

### Architecture (SOLID)
```
TForm1                    — UI only; holds FSocket, FRenderer, FFileService, FPrintService
IZplRenderer              — interface for rendering engines
TLabelaryRenderer         — implements IZplRenderer via HTTP POST
TZplSettingsManager       — INI read/write/defaults + LAN IP
TZplFileService           — PNG + raw ZPL file export
TZplPrintService          — physical printer (raw ZPL or GDI image)
```

### Key constraint
`TForm1` must NOT contain business logic. Rendering, file I/O, printing and settings persistence
all live in their respective service units. UI events call services; services never call UI.

### Settings record location
`ZViewSettings` record is defined in `zplview_settings.pas` (same file as the settings form).
All service units import from there.

### IZplRenderer contract
- Returns `True` + fills `Output: TMemoryStream` with PNG on success
- Returns `False` + sets `FLastError` on failure — never raises exceptions
- Stateless between calls

### When asked to add a feature, follow this checklist:
1. Does it belong in an existing service? Add a method there.
2. Does it require a new type of operation? Create a new service unit.
3. Does it need a new setting? Update `ZViewSettings` → `TZplSettingsManager` → `TFormSettings`.
4. Does it change rendering? Implement `IZplRenderer`, swap in `FormCreate`.
5. Keep `TForm1` as a thin coordinator — no HTTP, no INI, no printer API calls there.

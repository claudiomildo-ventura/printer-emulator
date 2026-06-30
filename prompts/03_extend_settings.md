# Extending ZViewSettings

## Goal
Add a new configuration field (e.g. `apikey`, `timeout`, `renderengine`) that persists to INI
and appears in the settings dialog.

## Files to touch (in order)

1. `zplview_settings.pas` — add field to `ZViewSettings` record
2. `zplview_settings_manager.pas` — add Read/Write calls
3. `zplview_settings.pas` (`TFormSettings`) — add UI control + wire in `PutSettings`/`GetSettings`
4. `zplview_settings.lfm` — add the visual component (or do it in Lazarus IDE)

---

## Step 1 — Add field to the record

```pascal
// zplview_settings.pas
ZViewSettings = record
  // ... existing fields ...
  apikey: string;       // ← new field
  timeout: integer;     // ← new field (seconds)
end;
```

## Step 2 — Persist in TZplSettingsManager

```pascal
// zplview_settings_manager.pas — Load procedure
apikey  := INI.ReadString('SETTINGS', 'apikey', '');
timeout := INI.ReadInteger('SETTINGS', 'timeout', 30);

// Save procedure
INI.WriteString('SETTINGS', 'apikey', apikey);
INI.WriteInteger('SETTINGS', 'timeout', timeout);

// LoadDefaults procedure
apikey  := '';
timeout := 30;
```

## Step 3 — Wire to settings dialog

```pascal
// TFormSettings.PutSettings
EdtApiKey.Text    := setup.apikey;
EdtTimeout.Text   := IntToStr(setup.timeout);

// TFormSettings.GetSettings
setup.apikey   := EdtApiKey.Text;
setup.timeout  := StrToIntDef(EdtTimeout.Text, 30);
```

## Step 4 — Add UI in the .lfm / IDE

Add a `TEdit` named `EdtApiKey` and a `TLabel` in `TFormSettings`.
The form uses absolute positioning — add below the last existing control.

---

## Notes

- `ZViewSettings` is a plain record (value type) — no constructor/destructor needed
- Default values in `LoadDefaults` and in `INI.ReadXxx` calls must match
- The `executescript` / `scriptpath` fields exist but are not implemented — safe to follow same pattern

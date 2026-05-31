unit zplcache;

{$mode objfpc}{$H+}

{ In-memory LRU cache for rendered label images.

  Key = MD5 hash of (ZPL data + rendering settings).
  Value = PNG image bytes stored in a TMemoryStream.

  The cache avoids redundant Labelary API calls when the same ZPL is rendered
  repeatedly with the same settings (e.g. on settings dialog cancel, rotation
  back to original, duplicate network jobs). }

interface

uses
  Classes, SysUtils, MD5, zplview_settings;

const
  DefaultMaxCacheEntries = 50;

type
  { TCacheEntry }
  TCacheEntry = class
  public
    Key: string;
    ImageData: TMemoryStream;
    Timestamp: TDateTime;
    constructor Create(const AKey: string; const AData: TMemoryStream);
    destructor Destroy; override;
  end;

  { TZplCache }
  TZplCache = class
  private
    FEntries: TList;
    FMaxEntries: integer;
    function FindEntry(const Key: string): integer;
    procedure Evict;
  public
    constructor Create(MaxEntries: integer = DefaultMaxCacheEntries);
    destructor Destroy; override;

    { Generates a cache key from ZPL data and settings. }
    class function MakeCacheKey(const ZplData: TMemoryStream;
      const Settings: ZViewSettings): string;

    { Tries to retrieve a cached image. Returns True if found, and copies
      the cached PNG data into ImageData (positioned at 0). }
    function TryGet(const Key: string; const ImageData: TMemoryStream): boolean;

    { Stores a rendered image in the cache. ImageData is COPIED. }
    procedure Put(const Key: string; const ImageData: TMemoryStream);

    { Number of entries currently in the cache. }
    function Count: integer;

    { Remove all cached entries. }
    procedure Clear;
  end;

implementation

{ TCacheEntry }

constructor TCacheEntry.Create(const AKey: string; const AData: TMemoryStream);
begin
  inherited Create;
  Key := AKey;
  Timestamp := Now;
  ImageData := TMemoryStream.Create;
  AData.Position := 0;
  ImageData.CopyFrom(AData, AData.Size);
  ImageData.Position := 0;
end;

destructor TCacheEntry.Destroy;
begin
  FreeAndNil(ImageData);
  inherited Destroy;
end;

{ TZplCache }

constructor TZplCache.Create(MaxEntries: integer);
begin
  inherited Create;
  FMaxEntries := MaxEntries;
  FEntries := TList.Create;
end;

destructor TZplCache.Destroy;
begin
  Clear;
  FreeAndNil(FEntries);
  inherited Destroy;
end;

class function TZplCache.MakeCacheKey(const ZplData: TMemoryStream;
  const Settings: ZViewSettings): string;
var
  Context: TMDContext;
  Digest: TMDDigest;
  SettingsStr: string;
begin
  SettingsStr := Format('%d|%d|%.4f|%.4f',
    [Settings.resolution, Settings.rotation, Settings.Width, Settings.Height]);

  MDInit(Context, MD_VERSION_5);

  ZplData.Position := 0;
  if ZplData.Size > 0 then
    MDUpdate(Context, ZplData.Memory^, ZplData.Size);

  MDUpdate(Context, SettingsStr[1], Length(SettingsStr));
  MDFinal(Context, Digest);

  Result := MDPrint(Digest);
  ZplData.Position := 0;
end;

function TZplCache.FindEntry(const Key: string): integer;
var
  I: integer;
begin
  for I := 0 to FEntries.Count - 1 do
    if TCacheEntry(FEntries[I]).Key = Key then
      Exit(I);
  Result := -1;
end;

procedure TZplCache.Evict;
var
  OldestIdx, I: integer;
  OldestTime: TDateTime;
  Entry: TCacheEntry;
begin
  if FEntries.Count = 0 then Exit;

  OldestIdx := 0;
  OldestTime := TCacheEntry(FEntries[0]).Timestamp;

  for I := 1 to FEntries.Count - 1 do
  begin
    Entry := TCacheEntry(FEntries[I]);
    if Entry.Timestamp < OldestTime then
    begin
      OldestIdx := I;
      OldestTime := Entry.Timestamp;
    end;
  end;

  TCacheEntry(FEntries[OldestIdx]).Free;
  FEntries.Delete(OldestIdx);
end;

function TZplCache.TryGet(const Key: string; const ImageData: TMemoryStream): boolean;
var
  Idx: integer;
  Entry: TCacheEntry;
begin
  Idx := FindEntry(Key);
  if Idx < 0 then
    Exit(False);

  Entry := TCacheEntry(FEntries[Idx]);
  Entry.Timestamp := Now; // refresh LRU timestamp

  ImageData.Clear;
  Entry.ImageData.Position := 0;
  ImageData.CopyFrom(Entry.ImageData, Entry.ImageData.Size);
  ImageData.Position := 0;

  Result := True;
end;

procedure TZplCache.Put(const Key: string; const ImageData: TMemoryStream);
var
  Idx: integer;
  Entry: TCacheEntry;
begin
  Idx := FindEntry(Key);
  if Idx >= 0 then
  begin
    // Update existing entry
    Entry := TCacheEntry(FEntries[Idx]);
    Entry.ImageData.Clear;
    ImageData.Position := 0;
    Entry.ImageData.CopyFrom(ImageData, ImageData.Size);
    Entry.ImageData.Position := 0;
    Entry.Timestamp := Now;
    Exit;
  end;

  // Evict if at capacity
  while FEntries.Count >= FMaxEntries do
    Evict;

  Entry := TCacheEntry.Create(Key, ImageData);
  FEntries.Add(Entry);
end;

function TZplCache.Count: integer;
begin
  Result := FEntries.Count;
end;

procedure TZplCache.Clear;
var
  I: integer;
begin
  for I := 0 to FEntries.Count - 1 do
    TCacheEntry(FEntries[I]).Free;
  FEntries.Clear;
end;

end.

unit uDoc;
{$mode objfpc}{$H+}
{ A text file held as a sliding window of lines.

  Lines are addressed by absolute 0-based line number. Only a window of roughly BUF_TARGET bytes is
  in memory (Lines, whose first entry is absolute line First). Everything before the window is parked
  in a "head" temp file, in chunks; everything after it is either in a "tail" temp file (lines that
  were pushed back out of the window, edits included) or still unread in the original file.
  Moving the window is called sliding: Seek brings a line, and some lines of margin around it, into
  memory, reading more at one end and parking lines at the other.

  Edits (SetLine, InsertLine, DeleteLine) only ever touch lines that are in the window. Anchors are
  absolute line numbers owned by others (cursors, block marks); they are adjusted on insert/delete. }

interface

uses SysUtils, Classes, BaseUnix, Unix, uText;

const
  BUF_TARGET   = 65536;      { nominal size of the in-memory window }
  CHUNK_BYTES  = 16384;      { size of one slide }
  MARGIN_LINES = 150;        { lines kept around the line being worked on }
  HARD_CAP     = 16 * 1024 * 1024;   { the window may grow this far to keep several views in memory }

type
  TEol = (eolLF, eolCRLF);

  TChunk = record
    off: Int64;
    nbytes: LongInt;
    nlines: LongInt;
  end;

  { A stack of line chunks kept in a temp file. The top is the chunk nearest to the window. }
  TChunkStack = class
  private
    f: THandle;
    path: string;
    top: Int64;
  public
    items: array of TChunk;
    cnt: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Push(src: TStrings; first, n: Integer);
    procedure PushRaw(const raw: string; nlines: Integer);
    procedure TransferTop(dst: TChunkStack);   { moves the top chunk, unparsed, onto dst }
    procedure Pop(dst: TStrings);          { appends the lines of the top chunk to dst }
    function ReadRaw(i: Integer): string;  { raw text of chunk i: every line followed by LF }
    procedure Clear;
    function TotalLines: Int64;
  end;

  TSrcReader = class
  private
    h: THandle;
    rbuf: array[0..65535] of Byte;
    rbase: Int64;
    rpos, rlen: Integer;
    fpos: Int64;
  public
    size: Int64;
    constructor Create(AHandle: THandle; ASize: Int64);
    destructor Destroy; override;
    procedure SeekTo(p: Int64);
    function Pos: Int64;
    function ReadLine(out s: string; out hadNL: Boolean): Boolean;
    function ReadRawBlock(var b; n: Integer): Integer;
    property Handle: THandle read h;
  end;

  PInt64 = ^Int64;

  { One undo step: every line edit made by one command (or one run of typing). }
  TUndoEntry = record
    kind: Byte;                { 0 = line replaced, 1 = line inserted, 2 = line deleted }
    line: Int64;
    oldText, newText: string;
  end;

  TUndoGroup = class
    entries: array of TUndoEntry;
    n: Integer;
    serial: Integer;
    beforeLine, afterLine: Int64;
    beforeCol, afterCol: Integer;
    mergeKey: Int64;           { typing on this line may be merged into the group }
    canMerge: Boolean;
    bytes: Int64;
  end;

  TDoc = class
  private
    FLines: TStringList;
    FFirst: Int64;
    FBytes: Int64;
    head, tail: TChunkStack;
    src: TSrcReader;
    anchors: array of PInt64;
    FUndo, FRedo: TList;
    FReplay: Boolean;
    FUndoBytes: Int64;
    FSavedTop: TUndoGroup;
    FStepLine: Int64;
    FStepCol: Integer;
    FStepKey: Int64;
    FStepSerial: Integer;
    procedure LogEntry(kind: Byte; line: Int64; const oldText, newText: string);
    procedure TrimUndo;
    procedure FreeGroups(l: TList);
    procedure Apply(g: TUndoGroup; undo: Boolean);
    function TopUndo: TUndoGroup;
    procedure AddBytes(n: Int64);
    function ReadMore: Boolean;
    function PopHead: Boolean;
    procedure ChopFront(n: Integer);
    procedure ChopBack(n: Integer);
    procedure PushHead(n: Integer);
    procedure PushTail(n: Integer);
    procedure TrimFront(line, pinLo: Int64);
    procedure TrimBack(line, pinHi: Int64);
    procedure AppendLine(const s: string);
    function EolStr: string;
  public
    Name: string;
    Modified: Boolean;
    NewFile: Boolean;
    Eol: TEol;
    NoFinalNL: Boolean;
    ExpandOnLoad: Boolean;
    TabW: Integer;
    Data: TObject;                 { owner's per-file data (kill buffer, saved position ...) }
    constructor Create(const AName: string; AExpandTabs: Boolean; ATabW: Integer);
    destructor Destroy; override;
    function HasMoreBefore: Boolean;
    function HasMoreAfter: Boolean;
    { Make line (absolute) available with margins; returns the line number actually reached
      (clamped to the file). pinLo/pinHi: another view's range that should stay in memory. }
    function Seek(line: Int64; pinLo: Int64 = High(Int64); pinHi: Int64 = -1): Int64;
    function InBuf(line: Int64): Boolean;
    function Get(line: Int64): string;
    procedure SetLine(line: Int64; const s: string);
    procedure InsertLine(line: Int64; const s: string);   { before line }
    procedure DeleteLine(line: Int64);
    function LastLineKnown: Boolean;
    function LastLine: Int64;       { only valid if LastLineKnown }
    function WindowBytes: Int64;
    function BufferFirst: Int64;
    function BufferCount: Integer;
    procedure AddAnchor(p: PInt64);
    procedure RemoveAnchor(p: PInt64);
    function Save(const dest: string; backup, tabsOut: Boolean; out err: string): Boolean;
    { Undo/redo. The application calls SetStep at the start of each command (cursor before it, and a
      key: typing on the same line merges into one step) and EndStep after it. }
    procedure SetStep(line: Int64; col: Integer; mergeKey: Int64);
    procedure EndStep(line: Int64; col: Integer);
    function Undo(out line: Int64; out col: Integer): Boolean;
    function Redo(out line: Int64; out col: Integer): Boolean;
    function UndoCount: Integer;
    function RedoCount: Integer;
    procedure MarkSaved;
    procedure ClearUndo;
  end;

var
  { bumped by the application for every command; edits with the same serial form one undo step }
  UndoSerial: Integer = 0;

function SplitLinesRaw(const raw: string; dst: TStrings): Integer;

implementation

var
  tmpSeq: Integer = 0;

{ Plain open(2) calls: FPC's FileOpen/FileCreate take flock() locks, which would keep other programs
  out of a file we are editing. }
function RawOpenRead(const path: string): THandle;
begin
  Result := THandle(fpOpen(path, O_RDONLY));
end;

function RawCreate(const path: string; mode: Integer; rw: Boolean = False): THandle;
begin
  if rw then Result := THandle(fpOpen(path, O_RDWR or O_CREAT or O_TRUNC, mode))
  else Result := THandle(fpOpen(path, O_WRONLY or O_CREAT or O_TRUNC, mode));
end;

function TempPath: string;
var
  d: string;
begin
  { parked text can be as large as the file, so prefer a disk-backed directory over /tmp (often tmpfs) }
  d := GetEnvironmentVariable('MKEDIT_TMP');
  if d = '' then d := GetEnvironmentVariable('TMPDIR');
  if (d = '') and (fpAccess('/var/tmp', W_OK) = 0) then d := '/var/tmp';
  if d = '' then d := '/tmp';
  Inc(tmpSeq);
  Result := IncludeTrailingPathDelimiter(d) + 'mkedit-' + IntToStr(GetProcessID) + '-' +
            IntToStr(tmpSeq) + '.tmp';
end;

function SplitLinesRaw(const raw: string; dst: TStrings): Integer;
var
  i, j, n: Integer;
begin
  n := 0;
  i := 1;
  while i <= Length(raw) do begin
    j := i;
    while (j <= Length(raw)) and (raw[j] <> #10) do Inc(j);
    dst.Add(Copy(raw, i, j - i));
    Inc(n);
    i := j + 1;
  end;
  Result := n;
end;

{ ------------------------------------------------------------ TChunkStack }

constructor TChunkStack.Create;
begin
  inherited Create;
  path := TempPath;
  f := RawCreate(path, &600, True);
  if f = THandle(-1) then raise Exception.Create('cannot create temp file ' + path);
  fpChmod(path, &600);
  top := 0;
  cnt := 0;
end;

destructor TChunkStack.Destroy;
begin
  if f <> THandle(-1) then FileClose(f);
  DeleteFile(path);
  inherited Destroy;
end;

procedure TChunkStack.Push(src: TStrings; first, n: Integer);
var
  i, total: Integer;
  raw: string;
  p: PChar;
begin
  total := 0;
  for i := first to first + n - 1 do Inc(total, Length(src[i]) + 1);
  SetLength(raw, total);
  p := PChar(raw);
  for i := first to first + n - 1 do begin
    if Length(src[i]) > 0 then Move(src[i][1], p^, Length(src[i]));
    Inc(p, Length(src[i]));
    p^ := #10;
    Inc(p);
  end;
  PushRaw(raw, n);
end;

procedure TChunkStack.PushRaw(const raw: string; nlines: Integer);
var
  total: Integer;
begin
  total := Length(raw);
  if cnt >= Length(items) then SetLength(items, cnt * 2 + 16);
  items[cnt].off := top;
  items[cnt].nbytes := total;
  items[cnt].nlines := nlines;
  Inc(cnt);
  FileSeek(f, top, fsFromBeginning);
  if total > 0 then
    if FileWrite(f, raw[1], total) <> total then raise Exception.Create('temp file write failed (disk full?)');
  Inc(top, total);
end;

procedure TChunkStack.TransferTop(dst: TChunkStack);
var
  raw: string;
  n: Integer;
begin
  raw := ReadRaw(cnt - 1);
  n := items[cnt - 1].nlines;
  top := items[cnt - 1].off;
  Dec(cnt);
  dst.PushRaw(raw, n);
end;

function TChunkStack.ReadRaw(i: Integer): string;
begin
  SetLength(Result, items[i].nbytes);
  if items[i].nbytes > 0 then begin
    FileSeek(f, items[i].off, fsFromBeginning);
    if FileRead(f, Result[1], items[i].nbytes) <> items[i].nbytes then
      raise Exception.Create('temp file read failed');
  end;
end;

procedure TChunkStack.Pop(dst: TStrings);
var
  raw: string;
begin
  raw := ReadRaw(cnt - 1);
  top := items[cnt - 1].off;
  Dec(cnt);
  SplitLinesRaw(raw, dst);
end;

procedure TChunkStack.Clear;
begin
  cnt := 0;
  top := 0;
end;

function TChunkStack.TotalLines: Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to cnt - 1 do Inc(Result, items[i].nlines);
end;

{ ------------------------------------------------------------ TSrcReader }

constructor TSrcReader.Create(AHandle: THandle; ASize: Int64);
begin
  inherited Create;
  h := AHandle;
  size := ASize;
  SeekTo(0);
end;

destructor TSrcReader.Destroy;
begin
  if h <> THandle(-1) then FileClose(h);
  inherited Destroy;
end;

procedure TSrcReader.SeekTo(p: Int64);
begin
  rbase := p;
  rpos := 0;
  rlen := 0;
  fpos := p;
end;

function TSrcReader.Pos: Int64;
begin
  Result := rbase + rpos;
end;

function TSrcReader.ReadLine(out s: string; out hadNL: Boolean): Boolean;
var
  j, n, old: Integer;
begin
  s := '';
  hadNL := False;
  Result := False;
  repeat
    if rpos >= rlen then begin
      rbase := fpos;
      FileSeek(h, fpos, fsFromBeginning);
      rlen := FileRead(h, rbuf, SizeOf(rbuf));
      if rlen < 0 then rlen := 0;
      rpos := 0;
      Inc(fpos, rlen);
      if rlen = 0 then Exit(Result);        { end of file; Result is True if a partial line was read }
    end;
    j := IndexByte(rbuf[rpos], rlen - rpos, 10);
    if j >= 0 then n := j else n := rlen - rpos;
    if n > 0 then begin
      old := Length(s);
      SetLength(s, old + n);
      Move(rbuf[rpos], s[old + 1], n);
    end;
    Inc(rpos, n);
    Result := True;
    if j >= 0 then begin
      Inc(rpos);
      hadNL := True;
      Exit;
    end;
  until False;
end;

function TSrcReader.ReadRawBlock(var b; n: Integer): Integer;
begin
  { reads from the current position straight from the file (used by Save) }
  FileSeek(h, Pos, fsFromBeginning);
  Result := FileRead(h, b, n);
  if Result > 0 then SeekTo(Pos + Result);
end;

{ ------------------------------------------------------------ TDoc }

constructor TDoc.Create(const AName: string; AExpandTabs: Boolean; ATabW: Integer);
var
  h: THandle;
  sz: Int64;
  probe: array[0..65535] of Byte;
  n, j: Integer;
begin
  inherited Create;
  Name := AName;
  ExpandOnLoad := AExpandTabs;
  TabW := ATabW;
  FLines := TStringList.Create;
  FUndo := TList.Create;
  FRedo := TList.Create;
  head := TChunkStack.Create;
  tail := TChunkStack.Create;
  FFirst := 0;
  FBytes := 0;
  Eol := eolLF;
  NoFinalNL := False;
  Modified := False;
  NewFile := True;
  src := nil;
  if (Name <> '') and FileExists(Name) then begin
    h := RawOpenRead(Name);
    if h = THandle(-1) then raise Exception.Create('cannot open ' + Name);
    sz := FileSeek(h, 0, fsFromEnd);
    FileSeek(h, 0, fsFromBeginning);
    NewFile := False;
    src := TSrcReader.Create(h, sz);
    n := FileRead(h, probe, SizeOf(probe));
    j := IndexByte(probe, n, 10);
    if (j > 0) and (probe[j - 1] = 13) then Eol := eolCRLF;
    { a NUL byte means binary data: never touch its tabs }
    if (n > 0) and (IndexByte(probe, n, 0) >= 0) then ExpandOnLoad := False;
    if sz > 0 then begin
      { does the file end with a newline? }
      FileSeek(h, sz - 1, fsFromBeginning);
      if (FileRead(h, probe, 1) = 1) and (probe[0] <> 10) then NoFinalNL := True;
    end;
    src.SeekTo(0);
    { initial window }
    while (FBytes < BUF_TARGET) and ReadMore do ;
  end;
  if FLines.Count = 0 then begin
    FLines.Add('');
    FBytes := 1;
  end;
end;

destructor TDoc.Destroy;
begin
  FreeGroups(FUndo);
  FreeGroups(FRedo);
  FUndo.Free;
  FRedo.Free;
  FLines.Free;
  head.Free;
  tail.Free;
  src.Free;
  inherited Destroy;
end;

function TDoc.EolStr: string;
begin
  if Eol = eolCRLF then Result := #13#10 else Result := #10;
end;

procedure TDoc.AddBytes(n: Int64);
begin
  Inc(FBytes, n);
end;

function TDoc.HasMoreBefore: Boolean;
begin
  Result := head.cnt > 0;
end;

function TDoc.HasMoreAfter: Boolean;
begin
  Result := (tail.cnt > 0) or ((src <> nil) and (src.Pos < src.size));
end;

function TDoc.LastLineKnown: Boolean;
begin
  Result := not HasMoreAfter;
end;

function TDoc.LastLine: Int64;
begin
  Result := FFirst + FLines.Count - 1;
end;

function TDoc.WindowBytes: Int64;
begin
  Result := FBytes;
end;

function TDoc.BufferFirst: Int64;
begin
  Result := FFirst;
end;

function TDoc.BufferCount: Integer;
begin
  Result := FLines.Count;
end;

procedure TDoc.AppendLine(const s: string);
begin
  FLines.Add(s);
  Inc(FBytes, Length(s) + 1);
end;

{ Append the next chunk after the window. }
function TDoc.ReadMore: Boolean;
var
  got: Int64;
  s: string;
  nl: Boolean;
  before: Integer;
begin
  Result := False;
  if tail.cnt > 0 then begin
    before := FLines.Count;
    tail.Pop(FLines);
    got := 0;
    while before < FLines.Count do begin Inc(got, Length(FLines[before]) + 1); Inc(before); end;
    Inc(FBytes, got);
    Exit(True);
  end;
  if (src = nil) or (src.Pos >= src.size) then Exit;
  got := 0;
  while got < CHUNK_BYTES do begin
    if not src.ReadLine(s, nl) then Break;
    if (Eol = eolCRLF) and (Length(s) > 0) and (s[Length(s)] = #13) then SetLength(s, Length(s) - 1);
    if ExpandOnLoad and (Pos(#9, s) > 0) then s := ExpandTabs(s, TabW);
    AppendLine(s);
    Inc(got, Length(s) + 1);
    Result := True;
  end;
end;

{ Prepend the nearest head chunk. }
function TDoc.PopHead: Boolean;
var
  tmp: TStringList;
  i: Integer;
  b: Int64;
begin
  Result := False;
  if head.cnt = 0 then Exit;
  tmp := TStringList.Create;
  try
    head.Pop(tmp);
    b := 0;
    for i := 0 to tmp.Count - 1 do Inc(b, Length(tmp[i]) + 1);
    for i := 0 to FLines.Count - 1 do tmp.Add(FLines[i]);
    FLines.Free;
    FLines := tmp;
    tmp := nil;
  finally
    tmp.Free;
  end;
  Dec(FFirst, head.items[head.cnt].nlines);   { cnt was decremented by Pop; items[cnt] is the popped chunk }
  Inc(FBytes, b);
  Result := True;
end;

procedure TDoc.ChopFront(n: Integer);
var
  nl: TStringList;
  i: Integer;
  b: Int64;
begin
  b := 0;
  for i := 0 to n - 1 do Inc(b, Length(FLines[i]) + 1);
  nl := TStringList.Create;
  nl.Capacity := FLines.Count - n + 64;
  for i := n to FLines.Count - 1 do nl.Add(FLines[i]);
  FLines.Free;
  FLines := nl;
  Dec(FBytes, b);
  Inc(FFirst, n);
end;

procedure TDoc.ChopBack(n: Integer);
var
  i: Integer;
  b: Int64;
begin
  b := 0;
  for i := FLines.Count - n to FLines.Count - 1 do Inc(b, Length(FLines[i]) + 1);
  for i := 1 to n do FLines.Delete(FLines.Count - 1);
  Dec(FBytes, b);
end;

procedure TDoc.PushHead(n: Integer);
begin
  head.Push(FLines, 0, n);
  ChopFront(n);
end;

procedure TDoc.PushTail(n: Integer);
begin
  tail.Push(FLines, FLines.Count - n, n);
  ChopBack(n);
end;

{ Park lines at the front while the window is over its size, but never lines at or after
  min(line, pinLo) - MARGIN_LINES. }
procedure TDoc.TrimFront(line, pinLo: Int64);
var
  limit, eligible: Int64;
  n: Integer;
  b: Int64;
begin
  while FBytes > BUF_TARGET do begin
    if (FBytes > HARD_CAP) or (pinLo = High(Int64)) then limit := line else limit := pinLo;
    if limit > line then limit := line;
    limit := limit - MARGIN_LINES;
    eligible := limit - FFirst;
    if eligible > FLines.Count - 1 then eligible := FLines.Count - 1;
    if eligible <= 0 then Break;
    n := 0; b := 0;
    while (n < eligible) and (b < CHUNK_BYTES) do begin
      Inc(b, Length(FLines[n]) + 1);
      Inc(n);
    end;
    if n = 0 then Break;
    PushHead(n);
  end;
end;

procedure TDoc.TrimBack(line, pinHi: Int64);
var
  limit, eligible: Int64;
  n: Integer;
  b: Int64;
begin
  while FBytes > BUF_TARGET do begin
    if (FBytes > HARD_CAP) or (pinHi < 0) then limit := line else limit := pinHi;
    if limit < line then limit := line;
    limit := limit + MARGIN_LINES;
    eligible := (FFirst + FLines.Count - 1) - limit;
    if eligible > FLines.Count - 1 then eligible := FLines.Count - 1;
    if eligible <= 0 then Break;
    n := 0; b := 0;
    while (n < eligible) and (b < CHUNK_BYTES) do begin
      Inc(b, Length(FLines[FLines.Count - 1 - n]) + 1);
      Inc(n);
    end;
    if n = 0 then Break;
    PushTail(n);
  end;
end;

function TDoc.Seek(line: Int64; pinLo: Int64; pinHi: Int64): Int64;
var
  n: Integer;
begin
  if line < 0 then line := 0;
  { Far jump over parked text: move whole chunks from one stack to the other without parsing them. }
  if pinHi < 0 then begin
    if (line < FFirst) and (head.cnt > 0) and (line < FFirst - head.items[head.cnt - 1].nlines) then begin
      if FLines.Count > 0 then PushTail(FLines.Count);
      while (head.cnt > 0) and (line < FFirst - head.items[head.cnt - 1].nlines) do begin
        n := head.items[head.cnt - 1].nlines;
        head.TransferTop(tail);
        Dec(FFirst, n);
      end;
    end else if (line >= FFirst + FLines.Count) and (tail.cnt > 0) and
                (line >= FFirst + FLines.Count + tail.items[tail.cnt - 1].nlines) then begin
      if FLines.Count > 0 then PushHead(FLines.Count);
      while (tail.cnt > 0) and (line >= FFirst + tail.items[tail.cnt - 1].nlines) do begin
        n := tail.items[tail.cnt - 1].nlines;
        tail.TransferTop(head);
        Inc(FFirst, n);
      end;
    end;
  end;
  while line < FFirst do begin
    if not PopHead then begin line := FFirst; Break; end;
    TrimBack(line, pinHi);
  end;
  while line >= FFirst + FLines.Count do begin
    if not ReadMore then begin line := FFirst + FLines.Count - 1; Break; end;
    TrimFront(line, pinLo);
  end;
  while (line - FFirst < MARGIN_LINES) and PopHead do ;
  while (FFirst + FLines.Count - 1 - line < MARGIN_LINES) and ReadMore do ;
  TrimFront(line, pinLo);
  TrimBack(line, pinHi);
  if line < FFirst then line := FFirst;
  if line > FFirst + FLines.Count - 1 then line := FFirst + FLines.Count - 1;
  Result := line;
end;

function TDoc.InBuf(line: Int64): Boolean;
begin
  Result := (line >= FFirst) and (line < FFirst + FLines.Count);
end;

function TDoc.Get(line: Int64): string;
begin
  if InBuf(line) then Result := FLines[line - FFirst] else Result := '';
end;

procedure TDoc.SetLine(line: Int64; const s: string);
var
  i: Integer;
begin
  if not InBuf(line) then Exit;
  i := line - FFirst;
  if not FReplay then LogEntry(0, line, FLines[i], s);
  Inc(FBytes, Length(s) - Length(FLines[i]));
  FLines[i] := s;
  Modified := True;
end;

procedure TDoc.InsertLine(line: Int64; const s: string);
var
  i: Integer;
begin
  if line < FFirst then line := FFirst;
  if line > FFirst + FLines.Count then line := FFirst + FLines.Count;
  if not FReplay then LogEntry(1, line, '', s);
  FLines.Insert(line - FFirst, s);
  Inc(FBytes, Length(s) + 1);
  for i := 0 to High(anchors) do
    if anchors[i]^ >= line then Inc(anchors[i]^);
  Modified := True;
end;

procedure TDoc.DeleteLine(line: Int64);
var
  i: Integer;
begin
  if not InBuf(line) then Exit;
  if not FReplay then LogEntry(2, line, FLines[line - FFirst], '');
  Dec(FBytes, Length(FLines[line - FFirst]) + 1);
  FLines.Delete(line - FFirst);
  for i := 0 to High(anchors) do
    if anchors[i]^ > line then Dec(anchors[i]^);
  Modified := True;
  if (FLines.Count = 0) then begin
    { the window ran dry: refill from either side, or leave one empty line if the file is empty }
    if not ReadMore then begin
      if (head.cnt > 0) and PopHead then begin end
      else if not FReplay then begin
        { the only line went: an empty file keeps one empty line (logged, so undo can restore it) }
        FLines.Add('');
        Inc(FBytes);
        LogEntry(1, line, '', '');
      end;
    end;
  end;
end;

{ ------------------------------------------------------------ undo / redo }

procedure TDoc.FreeGroups(l: TList);
var
  i: Integer;
begin
  for i := 0 to l.Count - 1 do TUndoGroup(l[i]).Free;
  l.Clear;
end;

function TDoc.TopUndo: TUndoGroup;
begin
  if FUndo.Count = 0 then Result := nil else Result := TUndoGroup(FUndo[FUndo.Count - 1]);
end;

function TDoc.UndoCount: Integer;
begin
  Result := FUndo.Count;
end;

function TDoc.RedoCount: Integer;
begin
  Result := FRedo.Count;
end;

procedure TDoc.SetStep(line: Int64; col: Integer; mergeKey: Int64);
begin
  FStepLine := line;
  FStepCol := col;
  FStepKey := mergeKey;
  FStepSerial := UndoSerial;
end;

procedure TDoc.EndStep(line: Int64; col: Integer);
var
  g: TUndoGroup;
begin
  g := TopUndo;
  if (g <> nil) and (g.serial = UndoSerial) then begin
    g.afterLine := line;
    g.afterCol := col;
  end;
end;

procedure TDoc.ClearUndo;
begin
  FreeGroups(FUndo);
  FreeGroups(FRedo);
  FUndoBytes := 0;
  FSavedTop := nil;
end;

procedure TDoc.MarkSaved;
var
  g: TUndoGroup;
begin
  g := TopUndo;
  if g <> nil then g.canMerge := False;      { later typing must not change the saved state }
  FSavedTop := g;
end;

{ Keep the log within bounds: drop the oldest steps. }
procedure TDoc.TrimUndo;
var
  g: TUndoGroup;
begin
  while (FUndoBytes > 64 * 1024 * 1024) or (FUndo.Count > 100000) do begin
    g := TUndoGroup(FUndo[0]);
    if g = FSavedTop then FSavedTop := nil;
    Dec(FUndoBytes, g.bytes);
    FUndo.Delete(0);
    g.Free;
  end;
end;

procedure TDoc.LogEntry(kind: Byte; line: Int64; const oldText, newText: string);
var
  g: TUndoGroup;
  e: TUndoEntry;
  sz: Int64;
begin
  if FRedo.Count > 0 then FreeGroups(FRedo);
  g := TopUndo;
  if not ((g <> nil) and (g.serial = UndoSerial)) then begin
    { a new command: merge plain typing on the same line into the previous step, else start a step }
    if (g <> nil) and (FStepSerial = UndoSerial) and (FStepKey >= 0) and g.canMerge and
       (g.mergeKey = FStepKey) and (g.afterLine = FStepLine) and (g.afterCol = FStepCol) and (g.n < 64) then
      g.serial := UndoSerial
    else begin
      g := TUndoGroup.Create;
      g.serial := UndoSerial;
      if FStepSerial = UndoSerial then begin
        g.beforeLine := FStepLine; g.beforeCol := FStepCol; g.mergeKey := FStepKey;
      end else begin
        g.beforeLine := line; g.beforeCol := 0; g.mergeKey := -1;
      end;
      g.afterLine := g.beforeLine; g.afterCol := g.beforeCol;
      g.canMerge := g.mergeKey >= 0;
      FUndo.Add(g);
    end;
  end;
  if (kind <> 0) or (line <> g.mergeKey) then g.canMerge := False;
  e.kind := kind; e.line := line; e.oldText := oldText; e.newText := newText;
  if g.n >= Length(g.entries) then SetLength(g.entries, g.n * 2 + 4);
  g.entries[g.n] := e;
  Inc(g.n);
  sz := Length(oldText) + Length(newText) + 48;
  Inc(g.bytes, sz);
  Inc(FUndoBytes, sz);
  TrimUndo;
end;

procedure TDoc.Apply(g: TUndoGroup; undo: Boolean);
var
  i: Integer;
  e: TUndoEntry;
begin
  FReplay := True;
  try
    if undo then begin
      for i := g.n - 1 downto 0 do begin
        e := g.entries[i];
        case e.kind of
          0: begin Seek(e.line); SetLine(e.line, e.oldText); end;
          1: begin Seek(e.line); DeleteLine(e.line); end;
          2: begin
            if e.line > 0 then Seek(e.line - 1) else Seek(0);
            InsertLine(e.line, e.oldText);
          end;
        end;
      end;
    end else begin
      for i := 0 to g.n - 1 do begin
        e := g.entries[i];
        case e.kind of
          0: begin Seek(e.line); SetLine(e.line, e.newText); end;
          1: begin
            if e.line > 0 then Seek(e.line - 1) else Seek(0);
            InsertLine(e.line, e.newText);
          end;
          2: begin Seek(e.line); DeleteLine(e.line); end;
        end;
      end;
    end;
  finally
    FReplay := False;
  end;
  if FLines.Count = 0 then begin FLines.Add(''); Inc(FBytes); end;
end;

function TDoc.Undo(out line: Int64; out col: Integer): Boolean;
var
  g: TUndoGroup;
begin
  Result := False;
  g := TopUndo;
  if g = nil then Exit;
  FUndo.Delete(FUndo.Count - 1);
  Dec(FUndoBytes, g.bytes);
  Apply(g, True);
  g.canMerge := False;
  FRedo.Add(g);
  line := g.beforeLine;
  col := g.beforeCol;
  Modified := TopUndo <> FSavedTop;
  Result := True;
end;

function TDoc.Redo(out line: Int64; out col: Integer): Boolean;
var
  g: TUndoGroup;
begin
  Result := False;
  if FRedo.Count = 0 then Exit;
  g := TUndoGroup(FRedo[FRedo.Count - 1]);
  FRedo.Delete(FRedo.Count - 1);
  Apply(g, False);
  FUndo.Add(g);
  Inc(FUndoBytes, g.bytes);
  line := g.afterLine;
  col := g.afterCol;
  Modified := TopUndo <> FSavedTop;
  Result := True;
end;

procedure TDoc.AddAnchor(p: PInt64);
begin
  SetLength(anchors, Length(anchors) + 1);
  anchors[High(anchors)] := p;
end;

procedure TDoc.RemoveAnchor(p: PInt64);
var
  i, j: Integer;
begin
  for i := 0 to High(anchors) do
    if anchors[i] = p then begin
      for j := i to High(anchors) - 1 do anchors[j] := anchors[j + 1];
      SetLength(anchors, Length(anchors) - 1);
      Exit;
    end;
end;

{ ------------------------------------------------------------ Save }

type
  TOut = class
    h: THandle;
    buf: string;
    pos: Int64;
    err: Boolean;
    constructor Create(AH: THandle);
    procedure Put(const s: string);
    procedure Flush;
  end;

constructor TOut.Create(AH: THandle);
begin
  h := AH; buf := ''; pos := 0; err := False;
end;

procedure TOut.Put(const s: string);
begin
  buf := buf + s;
  Inc(pos, Length(s));
  if Length(buf) >= 65536 then Flush;
end;

procedure TOut.Flush;
begin
  if Length(buf) > 0 then begin
    if FileWrite(h, buf[1], Length(buf)) <> Length(buf) then err := True;
    buf := '';
  end;
end;

function TDoc.Save(const dest: string; backup, tabsOut: Boolean; out err: string): Boolean;
var
  tmpName, bakName, target, eols, raw, ln: string;
  fh: THandle;
  o: TOut;
  i, a, b, k: Integer;
  posAfterBuffer: Int64;
  rawbuf: array[0..65535] of Byte;
  n: Integer;
  st: Stat;
  haveStat, remainder: Boolean;
  oldSrc: TSrcReader;
  newH: THandle;

  procedure PutLine(const s: string; omitEol: Boolean);
  var
    t: string;
  begin
    t := s;
    if tabsOut and (Pos('  ', t) > 0) then t := CompressTabs(t, TabW);
    if omitEol then o.Put(t) else o.Put(t + eols);
  end;

  procedure PutRawChunk(const r: string; isLastOfDoc: Boolean);
  var
    p, q: Integer;
  begin
    p := 1;
    while p <= Length(r) do begin
      q := p;
      while (q <= Length(r)) and (r[q] <> #10) do Inc(q);
      PutLine(Copy(r, p, q - p), isLastOfDoc and (q >= Length(r)) and NoFinalNL);
      p := q + 1;
    end;
  end;

begin
  Result := False;
  err := '';
  target := dest;
  { follow a symbolic link so the link itself survives }
  for i := 1 to 8 do begin
    raw := fpReadLink(target);
    if raw = '' then Break;
    if raw[1] <> '/' then raw := ExtractFilePath(target) + raw;
    target := raw;
  end;
  eols := EolStr;
  tmpName := target + '.mkedit-' + IntToStr(GetProcessID) + '.tmp';
  fh := RawCreate(tmpName, &666);
  if fh = THandle(-1) then begin err := 'cannot create ' + tmpName; Exit; end;
  haveStat := fpStat(target, st) = 0;
  o := TOut.Create(fh);
  try
    remainder := (src <> nil) and (src.Pos < src.size);
    oldSrc := src;
    { 1. parked head }
    for i := 0 to head.cnt - 1 do PutRawChunk(head.ReadRaw(i), False);
    { 2. the window }
    for i := 0 to FLines.Count - 1 do
      PutLine(FLines[i], (i = FLines.Count - 1) and (tail.cnt = 0) and (not remainder) and NoFinalNL);
    posAfterBuffer := o.pos;
    { 3. lines pushed back out of the window, nearest first }
    for i := tail.cnt - 1 downto 0 do
      PutRawChunk(tail.ReadRaw(i), (i = 0) and (not remainder));
    { 4. the unread rest of the original, byte for byte }
    if remainder then begin
      repeat
        n := oldSrc.ReadRawBlock(rawbuf, SizeOf(rawbuf));
        if n <= 0 then Break;
        SetLength(raw, n);
        Move(rawbuf, raw[1], n);
        o.Put(raw);
      until False;
    end;
    o.Flush;
    if o.err then begin err := 'write failed (disk full?)'; FileClose(fh); DeleteFile(tmpName); Exit; end;
    { posAfterBuffer is an offset in bytes of the new file; the buffer-flush above kept o.pos exact }
  finally
    o.Free;
  end;
  fpFsync(fh);
  FileClose(fh);
  if haveStat then fpChmod(tmpName, st.st_mode and &7777);
  if backup and FileExists(target) then begin
    bakName := ChangeFileExt(target, '.bak');
    DeleteFile(bakName);
    if not RenameFile(target, bakName) then begin
      err := 'cannot make backup ' + bakName; DeleteFile(tmpName); Exit;
    end;
  end;
  if not RenameFile(tmpName, target) then begin
    err := 'cannot rename to ' + target; DeleteFile(tmpName); Exit;
  end;
  { the saved file becomes the source: unread and pushed-back lines are re-read from it }
  newH := RawOpenRead(target);
  if newH = THandle(-1) then begin err := 'saved, but cannot reopen ' + target; Exit; end;
  src := TSrcReader.Create(newH, FileSeek(newH, 0, fsFromEnd));
  src.SeekTo(posAfterBuffer);
  oldSrc.Free;
  tail.Clear;
  Name := dest;
  Modified := False;
  NewFile := False;
  MarkSaved;
  Result := True;
end;

end.

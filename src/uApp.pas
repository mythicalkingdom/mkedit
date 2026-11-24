unit uApp;
{$mode objfpc}{$H+}
{ The editor proper: windows, drawing, key dispatch and all commands. Method bodies are split over
  several include files by topic (app_*.inc). }

interface

uses
  SysUtils, Classes, BaseUnix, termio, Video, uCP437, uKeys, uScreen, uText, uDoc, uDefs;

const
  FileEditPrompt = 'File(s) to edit (a wildcard like *.c gives a pick list): <Esc = abort>';
  VERSION = '0.1.0';
  MAXWIN = 8;

var
  { colours: fg 0..15, bg 0..7; "color_NAME = fg,bg" in the config file changes them }
  cTextFg: Byte = 7;   cTextBg: Byte = 1;
  cBlockFg: Byte = 0;  cBlockBg: Byte = 7;
  cStatFg: Byte = 0;   cStatBg: Byte = 3;
  cStatOffFg: Byte = 0; cStatOffBg: Byte = 7;
  cMenuFg: Byte = 0;   cMenuBg: Byte = 7;
  cMenuSelFg: Byte = 15; cMenuSelBg: Byte = 0;
  cHotFg: Byte = 4;
  cBoxFg: Byte = 15;   cBoxBg: Byte = 3;
  cMsgFg: Byte = 15;   cMsgBg: Byte = 2;

type
  EHangup = class(Exception);

  TBlockKind = (bkNone, bkLine, bkStream, bkColumn);

  TScrap = class
    kind: TBlockKind;
    lines: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure CopyFrom(o: TScrap);
  end;

  TKillKind = (kkLine, kkFrag, kkBlock);
  TKillEntry = class
    kind: TKillKind;
    scrap: TScrap;
    destructor Destroy; override;
  end;

  TDocInfo = class
    kill: TList;
    svLine, svTop: Int64;
    svCol, svLeft: Integer;
    cmode: Boolean;
    expand: Boolean;       { Tab inserts blanks (True) or a physical tab character }
    constructor Create;
    destructor Destroy; override;
  end;

  TWin = class
    doc: TDoc;
    line, top: Int64;
    col, left: Integer;
    y, h: Integer;
    undoLine: Int64;
    undoText: string;
    undoValid: Boolean;
    prevLine: Int64;
    prevCol: Integer;
    prevValid: Boolean;
    boxDir: Integer;       { last box-drawing move: 0 none, 1 up, 2 right, 3 down, 4 left }
    boxMask: Integer;      { connections the cell held before we drew on it }
    boxLine: Int64;
    boxCol: Integer;
  end;

  TMacro = class
    keys: array of TKey;
  end;

  TApp = class
  private
    wins: array[0..MAXWIN - 1] of TWin;
    nwins, cur: Integer;
    zoomed: Boolean;
    docs: TList;
    running: Boolean;
    msgText: string;
    { options }
    optInsert, optIndent, optWrap, optBox, optMatching, optSmart, optExpand, optTabsOut, optBackup: Boolean;
    optCutLine, optLineBefore: Boolean;
    optTrim, optEof, optDelJoin, optReturnSplit, optDelWs, optLastPrompt: Boolean;
    killMax: Integer;
    defExts: TStringList;
    fOptsR: string;
    hlLine: Int64;
    hlCol, hlLen: Integer;
    cfgMacros: TStringList;
    expandMode: Integer;   { 0 = auto (keep the tabs of files that have them), 1 = on, 2 = off }
    rmargin, ptab, ctab, scrStep: Integer;
    printLeft, printPage: Integer;
    { search }
    fFind, fRepl, fOpts, fOptsF: string;
    { blocks }
    bDoc: TDoc;
    bKind: TBlockKind;
    bSL, bEL: Int64;
    bSC, bEC: Integer;
    bFollow, bIncl: Boolean;
    bHalf: Integer;        { 1: only ^KB given, 2: only ^KK given; the block is not shown yet }
    scrap: TScrap;
    scratch: TStringList;
    { keys and macros }
    bindMap: TStringList;
    pending: string;
    cmdKeys: Integer;
    inject: array of TKey;
    injPos: Integer;
    recording: Boolean;
    recKey: string;
    recBuf: array of TKey;
    macros: TStringList;
    scrapMacro: TMacro;
    pasting: Boolean;
    lastCmd: TCmd;
    resized: Boolean;
    { --- core --- }
    function CW: TWin;
    function CD: TDoc;
    function Info(d: TDoc): TDocInfo;
    procedure Msg(const s: string);
    function GetKey: TKey;
    procedure CheckResize;
    procedure Relayout;
    procedure HandleKey(const k: TKey);
    procedure Execute(cmd: TCmd);
    function NewDoc(const path: string): TDoc;
    function FindDoc(const path: string): TDoc;
    function DocIndex(d: TDoc): Integer;
    function IsCFile(const name: string): Boolean;
    function WantExpand(const name: string): Boolean;
    { --- windows --- }
    procedure AttachDoc(w: TWin; d: TDoc);
    procedure DetachDoc(w: TWin);
    procedure ShowDoc(w: TWin; d: TDoc);
    procedure PinRange(w: TWin; out lo, hi: Int64);
    procedure SyncWin(w: TWin);
    procedure Adjust(w: TWin);
    procedure GoLine(ln: Int64);
    procedure TrimEdited(newLine: Int64);
    procedure AskForFile(ph: TDoc);
    procedure SavePrev;
    { --- drawing --- }
    procedure DrawAll;
    procedure DrawWin(i: Integer);
    procedure DrawTextLine(w: TWin; y: Integer; ln: Int64);
    function StatusText(w: TWin): string;
    function BlockCols(d: TDoc; ln: Int64; out c1, c2: Integer): Boolean;
    function BlockRange(out l1: Int64; out c1: Integer; out l2: Int64; out c2: Integer): Boolean;
    procedure DrawMessage;
    procedure Refresh;
    { --- UI --- }
    function Prompt(const title, initial: string; out res: string): Boolean;
    function PromptInt(const title: string; def, lo, hi: Integer; out v: Integer): Boolean;
    function AskKey(const text, valid: string): Char;
    function PickFile(const spec: string; out res: string): Boolean;
    procedure ShowHelp;
    procedure RunMenu(start: Integer);
    { --- line helpers --- }
    function CurText: string;
    procedure SetCurText(const s: string);
    function CurIdx(const s: string; out pad: Integer): Integer;
    function TabStop: Integer;
    function EndCol(const s: string): Integer;
    procedure TypeText(const t: string);
    procedure TypeChar(const ch: string);
    procedure DoReturn;
    procedure DoBackspace;
    procedure DoDelCh;
    procedure DoTab(forward: Boolean);
    procedure DoWordRight;
    procedure DoWordLeft;
    procedure DoDelRtWord;
    procedure DoDelLtWord;
    procedure DoJoinLine;
    procedure DoSplitLine;
    procedure DoAlign;
    procedure DoGetPrev;
    procedure DoLiteral;
    procedure DoUnKill;
    procedure DoUndoLine;
    procedure DoWrapPara;
    procedure DoMatch;
    procedure DoBoxMove(dir: Integer);
    procedure KillPush(kind: TKillKind; sc: TScrap);
    procedure KillText(kind: TKillKind; const text: string);
    procedure DoWrapAt(const s: string; idx: Integer);
    { --- cursor motion --- }
    procedure MoveUp;
    procedure MoveDown;
    procedure MovePage(dir: Integer; half: Boolean);
    procedure ScrollView(dir: Integer; moveCursor: Boolean);
    procedure PlaceScreen(mode: Integer);
    procedure DoColors;
    procedure SaveColors;
    procedure DoGotoLine;
    procedure DoGotoBlock(atEnd: Boolean);
    procedure DoBegEndFile(atEnd: Boolean);
    { --- blocks --- }
    procedure ClearBlock;
    procedure SetBlockDoc(d: TDoc);
    procedure MarkToggle(kind: TBlockKind; incl: Boolean);
    procedure MarkBegin;
    procedure MarkEnd;
    procedure TrackBlock;
    function BlockActive: Boolean;
    function ExtractBlock(d: TDoc; kind: TBlockKind; l1: Int64; c1: Integer; l2: Int64; c2: Integer): TScrap;
    procedure RemoveBlock(d: TDoc; kind: TBlockKind; l1: Int64; c1: Integer; l2: Int64; c2: Integer);
    procedure InsertScrap(d: TDoc; sc: TScrap; line: Int64; col: Integer; over: Boolean;
                          out eL: Int64; out eC: Integer);
    procedure DoCopyMove(move, over: Boolean);
    procedure DoDeleteBlock;
    procedure DoCutCopy(cut: Boolean);
    procedure PasteScrap(sc: TScrap; over: Boolean);
    procedure DoPaste(over: Boolean);
    procedure DoShift(right: Boolean);
    procedure DoScratch(mode: Integer);
    function BlockOrLine(out sc: TScrap; out l1: Int64; out c1: Integer; out l2: Int64; out c2: Integer;
                         out kind: TBlockKind): Boolean;
    procedure DoReadBlock;
    procedure DoWriteBlock;
    { --- files --- }
    procedure OpenFiles(const spec: string);
    procedure OpenFile(const path: string);
    function SaveDoc(d: TDoc): Boolean;
    procedure CloseDoc(d: TDoc);
    procedure DoNextPrevFile(dir: Integer);
    procedure DoEditFile;
    procedure DoChangeName;
    procedure DoExit(mode: Integer);
    procedure DoGlobal(mode: Integer);
    procedure DoKillFile;
    procedure DoShell;
    procedure DoDos;
    procedure DoPrint(whole: Boolean);
    procedure DoPrintEject;
    { --- windows commands --- }
    procedure WinSplit;
    procedure WinClose;
    procedure WinOne;
    procedure WinNext(dir: Integer);
    procedure WinResize(grow: Boolean);
    { --- macros --- }
    procedure DoMacroRecord;
    procedure DoMacroPlay(const nm: string);
    procedure DoMacroFile(write: Boolean);
    { --- search --- }
    procedure DoFind(replace: Boolean);
    procedure DoRepeatFind;
    function FindText(const pat, opts: string; fromCursor: Boolean; out ln: Int64; out idx: Integer): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(files: TStringList; gotoLine: Int64);
    procedure Run;
    procedure EmergencySave;
    procedure LoadConfig;
    procedure BuildCfgMacros;
  end;

implementation

uses Math, DateUtils, Unix, StrUtils;

{ ===================================================================== small classes }

constructor TScrap.Create;
begin
  inherited Create;
  lines := TStringList.Create;
  kind := bkNone;
end;

destructor TScrap.Destroy;
begin
  lines.Free;
  inherited Destroy;
end;

procedure TScrap.CopyFrom(o: TScrap);
begin
  kind := o.kind;
  lines.Assign(o.lines);
end;

destructor TKillEntry.Destroy;
begin
  scrap.Free;
  inherited Destroy;
end;

constructor TDocInfo.Create;
begin
  inherited Create;
  kill := TList.Create;
end;

destructor TDocInfo.Destroy;
var
  i: Integer;
begin
  for i := 0 to kill.Count - 1 do TKillEntry(kill[i]).Free;
  kill.Free;
  inherited Destroy;
end;

{ ===================================================================== core }

constructor TApp.Create;
var
  sl: TStringList;
  i: Integer;
  s: string;
begin
  inherited Create;
  docs := TList.Create;
  scrap := TScrap.Create;
  scratch := TStringList.Create;
  scratch.CaseSensitive := False;
  macros := TStringList.Create;
  macros.CaseSensitive := True;
  bindMap := TStringList.Create;
  bindMap.CaseSensitive := True;
  bindMap.Sorted := True;
  bindMap.Duplicates := dupIgnore;
  sl := TStringList.Create;
  try
    DefaultBindings(sl);
    for i := 0 to sl.Count - 1 do bindMap.AddObject(sl[i], sl.Objects[i]);
  finally
    sl.Free;
  end;
  optInsert := True; optIndent := True; optWrap := False; optBox := False; optMatching := False;
  optSmart := False; optExpand := True; optTabsOut := False; optBackup := True;
  optCutLine := True; optLineBefore := False;
  optTrim := True; optEof := True; optDelJoin := True; optReturnSplit := True; optDelWs := True;
  optLastPrompt := True; killMax := 30; fOptsR := 'I'; hlLen := 0;
  defExts := TStringList.Create;
  cfgMacros := TStringList.Create;
  expandMode := 0;
  rmargin := 76; ptab := 8; ctab := 4; scrStep := 8;
  printLeft := 0; printPage := 0;
  fOpts := 'I'; fOptsF := 'I';
  bKind := bkNone;
  s := GetEnvironmentVariable('MKEDIT_BACKUP');
  if s = '0' then optBackup := False;
  nwins := 0; cur := 0; zoomed := False;
  running := True;
  lastCmd := cmNone;
end;

destructor TApp.Destroy;
var
  i: Integer;
begin
  for i := 0 to nwins - 1 do wins[i].Free;
  for i := 0 to docs.Count - 1 do begin
    Info(TDoc(docs[i])).Free;
    TDoc(docs[i]).Free;
  end;
  docs.Free;
  scrap.Free;
  for i := 0 to scratch.Count - 1 do TScrap(scratch.Objects[i]).Free;
  scratch.Free;
  for i := 0 to macros.Count - 1 do TMacro(macros.Objects[i]).Free;
  macros.Free;
  scrapMacro.Free;
  defExts.Free;
  for i := 0 to cfgMacros.Count - 1 do cfgMacros.Objects[i].Free;
  cfgMacros.Free;
  bindMap.Free;
  inherited Destroy;
end;

function TApp.CW: TWin;
begin
  Result := wins[cur];
end;

function TApp.CD: TDoc;
begin
  Result := wins[cur].doc;
end;

function TApp.Info(d: TDoc): TDocInfo;
begin
  Result := TDocInfo(d.Data);
end;

procedure TApp.Msg(const s: string);
begin
  msgText := s;
end;

function TApp.IsCFile(const name: string): Boolean;
var
  e: string;
begin
  e := LowerCase(ExtractFileExt(name));
  Result := (e = '.c') or (e = '.h') or (e = '.cpp') or (e = '.hpp') or (e = '.cc');
end;

function FileHasTabs(const path: string): Boolean;
var
  h: THandle;
  buf: array[0..65535] of Byte;
  n: Integer;
begin
  Result := False;
  h := THandle(fpOpen(path, O_RDONLY));
  if h = THandle(-1) then Exit;
  n := FileRead(h, buf, SizeOf(buf));
  FileClose(h);
  if n > 0 then Result := IndexByte(buf, n, 9) >= 0;
end;

function TApp.WantExpand(const name: string): Boolean;
var
  b, e: string;
begin
  case expandMode of
    1: Exit(True);
    2: Exit(False);
  end;
  { auto: a file that already has tabs keeps them (makefiles, Go and C sources ...) }
  b := LowerCase(ExtractFileName(name));
  e := ExtractFileExt(b);
  if (b = 'makefile') or (b = 'gnumakefile') or (e = '.mk') or (e = '.tsv') then Exit(False);
  Result := not FileHasTabs(name);
end;

function TApp.NewDoc(const path: string): TDoc;
var
  inf: TDocInfo;
begin
  Result := TDoc.Create(path, WantExpand(path), ptab);
  inf := TDocInfo.Create;
  inf.cmode := IsCFile(path);
  inf.expand := Result.ExpandOnLoad;
  Result.Data := inf;
  Result.AddAnchor(@inf.svLine);
  Result.AddAnchor(@inf.svTop);
end;

function TApp.FindDoc(const path: string): TDoc;
var
  i: Integer;
  p: string;
begin
  p := ExpandFileName(path);
  for i := 0 to docs.Count - 1 do
    if TDoc(docs[i]).Name = p then Exit(TDoc(docs[i]));
  Result := nil;
end;

function TApp.DocIndex(d: TDoc): Integer;
begin
  Result := docs.IndexOf(d);
end;

{ ===================================================================== windows }

procedure TApp.AttachDoc(w: TWin; d: TDoc);
begin
  w.doc := d;
  d.AddAnchor(@w.line);
  d.AddAnchor(@w.top);
  d.AddAnchor(@w.prevLine);
  d.AddAnchor(@w.undoLine);
end;

procedure TApp.DetachDoc(w: TWin);
begin
  if w.doc = nil then Exit;
  w.doc.RemoveAnchor(@w.line);
  w.doc.RemoveAnchor(@w.top);
  w.doc.RemoveAnchor(@w.prevLine);
  w.doc.RemoveAnchor(@w.undoLine);
  w.doc := nil;
end;

{ Put document d in window w, remembering where the old document's cursor was. }
procedure TApp.ShowDoc(w: TWin; d: TDoc);
var
  inf: TDocInfo;
begin
  if w.doc = d then Exit;
  if w.doc <> nil then begin
    inf := Info(w.doc);
    inf.svLine := w.line; inf.svTop := w.top; inf.svCol := w.col; inf.svLeft := w.left;
    DetachDoc(w);
  end;
  AttachDoc(w, d);
  inf := Info(d);
  w.line := inf.svLine; w.top := inf.svTop; w.col := inf.svCol; w.left := inf.svLeft;
  w.undoValid := False;
  w.prevValid := False;
  w.boxDir := 0;
  SyncWin(w);
end;

procedure TApp.PinRange(w: TWin; out lo, hi: Int64);
var
  i: Integer;
  o: TWin;
begin
  lo := High(Int64);
  hi := -1;
  for i := 0 to nwins - 1 do begin
    o := wins[i];
    if (o <> w) and (o.doc = w.doc) and ((not zoomed) or (o = w)) then begin
      if o.top < lo then lo := o.top;
      if o.top + o.h > hi then hi := o.top + o.h;
    end;
  end;
end;

procedure TApp.SyncWin(w: TWin);
var
  lo, hi: Int64;
begin
  PinRange(w, lo, hi);
  w.doc.Seek(w.top + w.h - 1, lo, hi);
  w.line := w.doc.Seek(w.line, lo, hi);
  if w.top < 0 then w.top := 0;
end;

procedure TApp.GoLine(ln: Int64);
var
  lo, hi: Int64;
begin
  TrimEdited(ln);
  PinRange(CW, lo, hi);
  CW.line := CD.Seek(ln, lo, hi);
end;

{ Remove trailing blanks from a line that was edited, when the cursor leaves it. }
procedure TApp.TrimEdited(newLine: Int64);
var
  t: string;
begin
  if optTrim and CW.undoValid and (CW.undoLine <> newLine) then begin
    if CD.InBuf(CW.undoLine) then begin
      t := CD.Get(CW.undoLine);
      if RTrim(t) <> t then CD.SetLine(CW.undoLine, RTrim(t));
    end;
    CW.undoValid := False;
  end;
end;

procedure TApp.SavePrev;
begin
  CW.prevLine := CW.line;
  CW.prevCol := CW.col;
  CW.prevValid := True;
end;

{ Scroll so that the cursor is on screen. }
procedure TApp.Adjust(w: TWin);
var
  rows: Integer;
begin
  rows := w.h - 1;
  if rows < 1 then rows := 1;
  if w.line < w.top then begin
    if w.top - w.line >= rows then w.top := w.line - rows div 2 else w.top := w.line;
  end else if w.line >= w.top + rows then begin
    if w.line - (w.top + rows - 1) >= rows then w.top := w.line - rows div 2
    else w.top := w.line - rows + 1;
  end;
  if w.top < 0 then w.top := 0;
  if w.col < 0 then w.col := 0;
  if w.col > MAXCOL then w.col := MAXCOL;
  if w.col < w.left then w.left := w.col
  else if w.col >= w.left + ScrW then w.left := w.col - ScrW + 1;
  if w.left < 0 then w.left := 0;
end;

procedure TApp.Relayout;
var
  i, y, total, vis: Integer;
begin
  if (nwins = 0) then Exit;
  total := ScrH;
  if zoomed or (nwins = 1) then begin
    for i := 0 to nwins - 1 do begin wins[i].y := 0; end;
    wins[cur].y := 0;
    wins[cur].h := total;
    Exit;
  end;
  { heights are kept as wanted; fix them so that they add up to the screen }
  vis := 0;
  for i := 0 to nwins - 1 do begin
    if wins[i].h < 3 then wins[i].h := 3;
    Inc(vis, wins[i].h);
  end;
  while vis > total do begin
    for i := nwins - 1 downto 0 do
      if (vis > total) and (wins[i].h > 3) then begin Dec(wins[i].h); Dec(vis); end;
    if vis > total then begin
      { cannot fit: drop windows from the end }
      Break;
    end;
  end;
  if vis < total then Inc(wins[nwins - 1].h, total - vis);
  y := 0;
  for i := 0 to nwins - 1 do begin
    wins[i].y := y;
    Inc(y, wins[i].h);
  end;
end;

{ ===================================================================== drawing }

function TApp.BlockRange(out l1: Int64; out c1: Integer; out l2: Int64; out c2: Integer): Boolean;
var
  sl, el: Int64;
  sc, ec: Integer;
begin
  Result := False;
  if (bKind = bkNone) or (bDoc = nil) or (bHalf <> 0) then Exit;
  sl := bSL; sc := bSC; el := bEL; ec := bEC;
  case bKind of
    bkLine: begin
      if sl <= el then begin l1 := sl; l2 := el; end else begin l1 := el; l2 := sl; end;
      c1 := 0; c2 := MaxInt;
    end;
    bkColumn: begin
      if sl <= el then begin l1 := sl; l2 := el; end else begin l1 := el; l2 := sl; end;
      if sc <= ec then begin c1 := sc; c2 := ec + 1; end else begin c1 := ec; c2 := sc + 1; end;
    end;
  else
    if (sl < el) or ((sl = el) and (sc <= ec)) then begin
      l1 := sl; c1 := sc; l2 := el; c2 := ec;
    end else begin
      l1 := el; c1 := ec; l2 := sl; c2 := sc;
    end;
    if bIncl then Inc(c2);
    if (l1 = l2) and (c2 <= c1) then Exit;
  end;
  Result := True;
end;

{ Columns of line ln (of document d) that are inside the marked block: [c1, c2) }
function TApp.BlockCols(d: TDoc; ln: Int64; out c1, c2: Integer): Boolean;
var
  bl1, bl2: Int64;
  bc1, bc2: Integer;
begin
  Result := False;
  if (d <> bDoc) or not BlockRange(bl1, bc1, bl2, bc2) then Exit;
  if (ln < bl1) or (ln > bl2) then Exit;
  case bKind of
    bkLine: begin c1 := 0; c2 := MaxInt; end;
    bkColumn: begin c1 := bc1; c2 := bc2; end;
  else
    if bl1 = bl2 then begin c1 := bc1; c2 := bc2; end
    else if ln = bl1 then begin c1 := bc1; c2 := MaxInt; end
    else if ln = bl2 then begin c1 := 0; c2 := bc2; end
    else begin c1 := 0; c2 := MaxInt; end;
  end;
  Result := True;
end;

procedure TApp.DrawTextLine(w: TWin; y: Integer; ln: Int64);
var
  s: string;
  i, col, n, k, tw, c1, c2, x, m: Integer;
  cp: Cardinal;
  b: Byte;
  hasBlk, blkHere, isLast: Boolean;
  fg, bg: Byte;
  width: Integer;
begin
  width := ScrW;
  ScrFill(0, y, width, 32, cTextFg, cTextBg);
  isLast := w.doc.LastLineKnown and (ln > w.doc.LastLine);
  if optEof and w.doc.LastLineKnown and (ln = w.doc.LastLine + 1) then
    ScrPutsN(0, y, '<*** End of File ***>', width, 15, cTextBg);
  if isLast or (not w.doc.InBuf(ln)) then Exit;
  s := w.doc.Get(ln);
  tw := ptab;
  hasBlk := BlockCols(w.doc, ln, c1, c2);
  col := 0;
  i := 1;
  while (i <= Length(s)) and (col < w.left + width) do begin
    if s[i] = #9 then begin
      n := tw - (col mod tw);
      b := 32;
      k := 1;
    end else begin
      n := 1;
      if Byte(s[i]) < $80 then begin b := Byte(s[i]); k := 1; end
      else begin
        k := Utf8Decode(@s[i], Length(s) - i + 1, cp);
        if k = 0 then begin b := Byte(s[i]); k := 1; end
        else begin
          m := UniToCp437(cp);
          if m < 0 then b := 63 else b := m;
        end;
      end;
    end;
    while n > 0 do begin
      if col >= w.left then begin
        x := col - w.left;
        blkHere := hasBlk and (col >= c1) and (col < c2);
        if blkHere then begin fg := cBlockFg; bg := cBlockBg; end else begin fg := cTextFg; bg := cTextBg; end;
        ScrPut(x, y, b, fg, bg);
      end;
      Inc(col);
      Dec(n);
    end;
    Inc(i, k);
  end;
  { the string just found }
  if (hlLen > 0) and (ln = hlLine) and (w = wins[cur]) then
    for x := hlCol to hlCol + hlLen - 1 do
      if (x >= w.left) and (x - w.left < width) then ScrAttr(x - w.left, y, 1, 0, 6);
  { block highlight beyond the end of the text }
  if hasBlk then begin
    if col < w.left then col := w.left;
    if c2 = MaxInt then begin
      { whole-line and continuing blocks: highlight one cell past the text for stream blocks }
      if bKind = bkLine then begin
        for x := col - w.left to width - 1 do ScrAttr(x, y, 1, cBlockFg, cBlockBg);
      end else if col - w.left < width then
        ScrAttr(col - w.left, y, 1, cBlockFg, cBlockBg);
    end else begin
      for x := Max(col, c1) to c2 - 1 do
        if (x >= w.left) and (x - w.left < width) then ScrAttr(x - w.left, y, 1, cBlockFg, cBlockBg);
    end;
  end;
end;

function TApp.StatusText(w: TWin): string;
var
  fl, nm, mem: string;
  active: Boolean;
begin
  active := (w = wins[cur]);
  fl := '';
  if optInsert then fl := fl + 'I' else fl := fl + ' ';
  if optIndent then fl := fl + 'A' else fl := fl + ' ';
  if optWrap then fl := fl + 'W' else fl := fl + ' ';
  fl := fl + ' ';
  if recording and active then fl := fl + 'R' else fl := fl + ' ';
  fl := fl + ' ';
  if optBox then fl := fl + 'B' else fl := fl + ' ';
  mem := IntToStr(w.doc.WindowBytes div 1024) + 'K';
  nm := w.doc.Name;
  if nm = '' then nm := '(no name)';
  if w.doc.Modified then nm := '*' + nm else nm := ' ' + nm;
  if w.doc.NewFile then nm := nm + ' (new)';
  Result := 'L ' + Format('%-6d', [w.line + 1]) + 'C ' + Format('%-5d', [w.col + 1]) + fl + '  ' +
            Format('%5s', [mem]) + '   ' + nm;
end;

procedure TApp.DrawWin(i: Integer);
var
  w: TWin;
  r, rows: Integer;
  fg, bg: Byte;
  st: string;
begin
  w := wins[i];
  if zoomed and (i <> cur) then Exit;
  if (nwins > 1) and (not zoomed) and (w.y >= ScrH) then Exit;
  rows := w.h - 1;
  SyncWin(w);
  if i = cur then begin fg := cStatFg; bg := cStatBg; end else begin fg := cStatOffFg; bg := cStatOffBg; end;
  ScrFill(0, w.y, ScrW, 32, fg, bg);
  st := StatusText(w);
  ScrPutsN(0, w.y, st, ScrW, fg, bg);
  for r := 0 to rows - 1 do DrawTextLine(w, w.y + 1 + r, w.top + r);
end;

procedure TApp.DrawMessage;
var
  s: string;
begin
  if msgText = '' then Exit;
  s := ' ' + msgText + ' ';
  ScrFill(0, ScrH - 1, ScrW, 32, cMsgFg, cMsgBg);
  ScrPutsN(0, ScrH - 1, s, ScrW, cMsgFg, cMsgBg);
end;

procedure TApp.DrawAll;
var
  i: Integer;
begin
  ScrClear(cTextFg, cTextBg);
  for i := 0 to nwins - 1 do
    if i <> cur then DrawWin(i);
  DrawWin(cur);     { last: leaves the cursor's document positioned for editing }
  DrawMessage;
end;

procedure TApp.Refresh;
begin
  Relayout;
  Adjust(CW);
  DrawAll;
  ScrCursor(CW.col - CW.left, CW.y + 1 + (CW.line - CW.top), not optInsert);
  ScrFlush;
end;

procedure TApp.CheckResize;
var
  ws: TWinSize;
  m: TVideoMode;
begin
  if fpIoctl(1, TIOCGWINSZ, @ws) = 0 then
    if (ws.ws_col > 0) and ((ws.ws_col <> ScreenWidth) or (ws.ws_row <> ScreenHeight)) then begin
      GetVideoMode(m);
      m.Col := ws.ws_col;
      m.Row := ws.ws_row;
      SetVideoMode(m);
      UpdateScreen(True);
      resized := True;
    end;
end;

{ ===================================================================== input }

function TApp.GetKey: TKey;
var
  k: TKey;
begin
  if injPos < Length(inject) then begin
    k := inject[injPos];
    Inc(injPos);
    if injPos >= Length(inject) then begin SetLength(inject, 0); injPos := 0; end;
    Result := k;
    Exit;
  end;
  repeat
    if KeyRead(k) then Break;
    if Hangup then raise EHangup.Create('terminal hangup');
    CheckResize;
    if resized then begin
      resized := False;
      k.code := kcNone; k.mods := []; k.ch := ''; k.n := 0;
      Result := k;
      Exit;
    end;
    KeyWait(100);
  until False;
  if recording and (k.code <> kcNone) and (k.code <> kcPasteBegin) and (k.code <> kcPasteEnd) then begin
    SetLength(recBuf, Length(recBuf) + 1);
    recBuf[High(recBuf)] := k;
  end;
  Result := k;
end;

function NormSecond(const k: TKey): string;
begin
  if (k.code = kcChar) and (Length(k.ch) = 1) and (k.ch[1] in ['A'..'Z', 'a'..'z']) then
    Result := LowerCase(k.ch)
  else
    Result := KeyName(k);
end;

procedure TApp.HandleKey(const k: TKey);
var
  nm, seq: string;
  i, p: Integer;
  cmd: TCmd;
  isPrefix: Boolean;
begin
  if k.code = kcNone then Exit;
  if k.code = kcPasteBegin then begin pasting := True; Exit; end;
  if k.code = kcPasteEnd then begin pasting := False; Exit; end;
  msgText := '';
  hlLen := 0;
  if pending <> '' then begin
    seq := pending + ' ' + NormSecond(k);
    pending := '';
    cmdKeys := 2;
    i := bindMap.IndexOf(seq);
    if i >= 0 then Execute(TCmd(PtrInt(bindMap.Objects[i])))
    else Msg('Unknown key sequence');
    Exit;
  end;
  cmdKeys := 1;
  nm := KeyName(k);
  isPrefix := False;
  for p := 0 to High(Prefixes) do
    if nm = Prefixes[p] then isPrefix := True;
  if isPrefix then begin
    pending := nm;
    Msg(KeyLabel(nm) + '-');
    Exit;
  end;
  if nm <> '' then begin
    i := macros.IndexOf(nm);
    if i >= 0 then begin DoMacroPlay(nm); Exit; end;
    i := bindMap.IndexOf(nm);
    if i >= 0 then begin
      cmd := TCmd(PtrInt(bindMap.Objects[i]));
      Execute(cmd);
      Exit;
    end;
  end;
  if (k.code = kcChar) and ((k.mods - [mShift]) = []) then begin
    TypeChar(k.ch);
    lastCmd := cmNone;
  end;
end;

procedure TApp.TrackBlock;
begin
  if bFollow and (bDoc = CD) and (bKind <> bkNone) then begin
    bEL := CW.line;
    bEC := CW.col;
  end;
end;

procedure TApp.Run;
var
  k: TKey;
begin
  while running do begin
    if nwins = 0 then Break;
    if injPos >= Length(inject) then Refresh else Adjust(CW);
    k := GetKey;
    HandleKey(k);
    if running and (nwins > 0) then begin
      TrimEdited(CW.line);
      TrackBlock;
      CW.doc.Seek(CW.line);
    end;
  end;
end;

{ ===================================================================== start / finish }

procedure TApp.Start(files: TStringList; gotoLine: Int64);
var
  i: Integer;
  w: TWin;
  ph: TDoc;
  sel: string;
begin
  w := TWin.Create;
  wins[0] := w;
  nwins := 1;
  cur := 0;
  w.h := ScrH;
  w.y := 0;
  for i := 0 to files.Count - 1 do begin
    if (i > 0) and (StrToIntDef(files[i], -1) > 0) and (docs.Count > 0) then GoLine(StrToInt(files[i]) - 1)
    else OpenFile(files[i]);
  end;
  if docs.Count = 0 then begin
    { nothing named on the command line: ask }
    ph := NewDoc('');
    docs.Add(ph);
    ShowDoc(w, ph);
    if Prompt(FileEditPrompt, '', sel) then OpenFiles(sel);
    if docs.Count > 1 then CloseDoc(ph) else running := False;
    msgText := '';
  end;
  if (not running) or (docs.Count = 0) then Exit;
  if gotoLine > 0 then begin
    GoLine(gotoLine - 1);
  end;
end;

{ The terminal has gone: keep the unsaved work as NAME.mkedit-save next to the original. }
procedure TApp.EmergencySave;
var
  i: Integer;
  d: TDoc;
  err: string;
begin
  for i := 0 to docs.Count - 1 do begin
    d := TDoc(docs[i]);
    if d.Modified and (d.Name <> '') then
      d.Save(d.Name + '.mkedit-save', False, False, err);
  end;
end;

{ "key F1 = MacroBegin EditFile 'help.dat' Return": commands become the keys that run them, quoted
  text becomes typed characters. }
procedure TApp.BuildCfgMacros;
var
  i, p, q, j, bi: Integer;
  nm, rest, tok, kstr, best: string;
  m: TMacro;
  c: TCmd;
  qc: Char;

  procedure AddKey(const k: TKey);
  begin
    SetLength(m.keys, Length(m.keys) + 1);
    m.keys[High(m.keys)] := k;
  end;

  procedure AddText(const t: string);
  var
    n, ix: Integer;
    k: TKey;
  begin
    ix := 1;
    while ix <= Length(t) do begin
      n := CharLen(t, ix);
      k.code := kcChar; k.mods := []; k.ch := Copy(t, ix, n); k.n := 0;
      AddKey(k);
      Inc(ix, n);
    end;
  end;

  procedure AddCmd(cmd: TCmd);
  var
    b, sp: Integer;
    bestk: string;
    k: TKey;
  begin
    bestk := '';
    for b := 0 to bindMap.Count - 1 do
      if TCmd(PtrInt(bindMap.Objects[b])) = cmd then
        if (bestk = '') or (Length(bindMap[b]) < Length(bestk)) then bestk := bindMap[b];
    if bestk = '' then Exit;
    sp := Pos(' ', bestk);
    if sp > 0 then begin
      AddKey(KeyFromName(Copy(bestk, 1, sp - 1)));
      AddKey(KeyFromName(Copy(bestk, sp + 1, MaxInt)));
    end else begin
      k := KeyFromName(bestk);
      AddKey(k);
    end;
  end;

begin
  for i := 0 to cfgMacros.Count - 1 do begin
    p := Pos(#9, cfgMacros[i]);
    nm := Copy(cfgMacros[i], 1, p - 1);
    rest := Trim(Copy(cfgMacros[i], p + 1, MaxInt));
    m := TMacro.Create;
    q := 1;
    while q <= Length(rest) do begin
      while (q <= Length(rest)) and (rest[q] = ' ') do Inc(q);
      if q > Length(rest) then Break;
      if rest[q] in ['''', '"'] then begin
        qc := rest[q];
        j := q + 1;
        while (j <= Length(rest)) and (rest[j] <> qc) do Inc(j);
        AddText(Copy(rest, q + 1, j - q - 1));
        q := j + 1;
      end else begin
        j := q;
        while (j <= Length(rest)) and (rest[j] <> ' ') do Inc(j);
        tok := Copy(rest, q, j - q);
        q := j;
        if SameText(tok, 'CurrentFilename') then begin
          AddKey(KeyFromName('F20'));   { placeholder, replaced by the file name when played }
          m.keys[High(m.keys)].code := kcNone;
          m.keys[High(m.keys)].n := 1;
        end else begin
          c := CmdByName(tok);
          if c <> cmNone then AddCmd(c);
        end;
      end;
    end;
    bi := macros.IndexOf(nm);
    if bi >= 0 then begin TMacro(macros.Objects[bi]).Free; macros.Delete(bi); end;
    macros.AddObject(nm, m);
  end;
end;

function ConfigDir: string;
begin
  Result := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if Result = '' then Result := GetEnvironmentVariable('HOME') + '/.config';
  Result := IncludeTrailingPathDelimiter(Result) + 'mkedit/';
end;

function BoolVal(const v: string): Boolean;
begin
  Result := (v = '1') or SameText(v, 'on') or SameText(v, 'yes') or SameText(v, 'true');
end;

{ ~/.config/mkedit/mkedit.cfg: "option = value" and "key <name> = <Command>" lines, # comments. }
procedure TApp.LoadConfig;
var
  fn, line, k, v, kn: string;
  sl: TStringList;
  i, p, n, j, m2: Integer;
  cmd: TCmd;
begin
  fn := ConfigDir + 'mkedit.cfg';
  if not FileExists(fn) then Exit;
  sl := TStringList.Create;
  try
    try
      sl.LoadFromFile(fn);
    except
      Exit;
    end;
    for i := 0 to sl.Count - 1 do begin
      line := Trim(sl[i]);
      if (line = '') or (line[1] = '#') then Continue;
      p := Pos('=', line);
      if p < 2 then Continue;
      k := LowerCase(Trim(Copy(line, 1, p - 1)));
      v := Trim(Copy(line, p + 1, MaxInt));
      n := StrToIntDef(v, -1);
      if k = 'insert' then optInsert := BoolVal(v)
      else if k = 'autoindent' then optIndent := BoolVal(v)
      else if k = 'wordwrap' then optWrap := BoolVal(v)
      else if k = 'backup' then optBackup := BoolVal(v)
      else if k = 'expandtabs' then begin
        if SameText(v, 'auto') then expandMode := 0 else if BoolVal(v) then expandMode := 1 else expandMode := 2;
      end
      else if k = 'tabsout' then optTabsOut := BoolVal(v)
      else if k = 'smarttabs' then optSmart := BoolVal(v)
      else if k = 'entermatching' then optMatching := BoolVal(v)
      else if k = 'cutcopyline' then optCutLine := BoolVal(v)
      else if k = 'lineblockbefore' then optLineBefore := BoolVal(v)
      else if k = 'trimblanks' then optTrim := BoolVal(v)
      else if k = 'eofmarker' then optEof := BoolVal(v)
      else if k = 'delchjoin' then optDelJoin := BoolVal(v)
      else if k = 'returnsplit' then optReturnSplit := BoolVal(v)
      else if k = 'delrtwordblanks' then optDelWs := BoolVal(v)
      else if k = 'lastfileprompt' then optLastPrompt := BoolVal(v)
      else if k = 'findoptions' then fOptsF := UpperCase(v)
      else if k = 'replaceoptions' then fOptsR := UpperCase(v)
      else if (k = 'killbuffer') and (n >= 0) and (n <= 300) then killMax := n
      else if k = 'extensions' then begin
        defExts.Clear;
        defExts.Delimiter := ' ';
        defExts.StrictDelimiter := True;
        defExts.DelimitedText := v;
      end
      else if Copy(k, 1, 6) = 'color_' then begin
        j := Pos(',', v);
        if j > 0 then begin
          n := StrToIntDef(Trim(Copy(v, 1, j - 1)), -1);
          m2 := StrToIntDef(Trim(Copy(v, j + 1, MaxInt)), -1);
          if (n >= 0) and (n <= 15) and (m2 >= 0) and (m2 <= 7) then begin
            kn := Copy(k, 7, MaxInt);
            if kn = 'text' then begin cTextFg := n; cTextBg := m2; end
            else if kn = 'block' then begin cBlockFg := n; cBlockBg := m2; end
            else if kn = 'status' then begin cStatFg := n; cStatBg := m2; end
            else if kn = 'statusoff' then begin cStatOffFg := n; cStatOffBg := m2; end
            else if kn = 'menu' then begin cMenuFg := n; cMenuBg := m2; end
            else if kn = 'menuselect' then begin cMenuSelFg := n; cMenuSelBg := m2; end
            else if kn = 'box' then begin cBoxFg := n; cBoxBg := m2; end
            else if kn = 'message' then begin cMsgFg := n; cMsgBg := m2; end
            else if kn = 'menuhot' then cHotFg := n;
          end;
        end;
      end
      else if (k = 'rmargin') and (n >= 1) and (n <= 300) then rmargin := n
      else if (k = 'tabwidth') and (n >= 1) and (n <= 16) then ptab := n
      else if (k = 'ctabwidth') and (n >= 1) and (n <= 16) then ctab := n
      else if (k = 'screenstep') and (n >= 1) and (n <= 100) then scrStep := n
      else if Copy(k, 1, 4) = 'key ' then begin
        { key C-k a = DropAnchor   (several keys separated by single spaces form a sequence) }
        kn := Trim(Copy(line, 5, p - 5));
        cmd := CmdByName(v);
        j := bindMap.IndexOf(kn);
        if SameText(Copy(v, 1, 10), 'MacroBegin') then begin
          cfgMacros.Add(kn + #9 + Copy(v, 11, MaxInt));
        end else if SameText(v, 'none') then begin
          if j >= 0 then bindMap.Delete(j);
        end else if cmd <> cmNone then begin
          if j >= 0 then bindMap.Delete(j);
          bindMap.AddObject(kn, TObject(PtrInt(Ord(cmd))));
        end;
      end;
    end;
  finally
    sl.Free;
  end;
  BuildCfgMacros;
end;

{$I app_edit.inc}
{$I app_block.inc}
{$I app_files.inc}
{$I app_search.inc}
{$I app_ui.inc}

end.

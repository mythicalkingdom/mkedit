{ ===================================================================== line helpers }

function TApp.TabStop: Integer;
begin
  Result := ptab;
end;

function TApp.CurText: string;
begin
  Result := CD.Get(CW.line);
end;

{ Replace the cursor line, remembering the original text for UndoCursorline. }
procedure TApp.SetCurText(const s: string);
begin
  if not (CW.undoValid and (CW.undoLine = CW.line)) then begin
    CW.undoText := CD.Get(CW.line);
    CW.undoLine := CW.line;
    CW.undoValid := True;
  end;
  CD.SetLine(CW.line, s);
end;

function TApp.CurIdx(const s: string; out pad: Integer): Integer;
begin
  Result := IdxOfCol(s, CW.col, TabStop, pad);
end;

{ column just after the last non-blank character }
function TApp.EndCol(const s: string): Integer;
var
  i: Integer;
begin
  i := LastNonBlank(s);
  if i = 0 then Exit(0);
  Result := ColOfIdx(s, CharNext(s, i), TabStop);
end;

procedure TApp.KillPush(kind: TKillKind; sc: TScrap);
var
  inf: TDocInfo;
  e: TKillEntry;
begin
  inf := Info(CD);
  e := TKillEntry.Create;
  e.kind := kind;
  e.scrap := sc;
  inf.kill.Add(e);
  while inf.kill.Count > killMax do begin
    TKillEntry(inf.kill[0]).Free;
    inf.kill.Delete(0);
  end;
end;

procedure TApp.KillText(kind: TKillKind; const text: string);
var
  sc: TScrap;
begin
  sc := TScrap.Create;
  sc.kind := bkStream;
  sc.lines.Add(text);
  KillPush(kind, sc);
end;

{ ===================================================================== typing }

{ Wrap the line at idx (the position where a character is about to be typed) if the margin has been
  passed. Returns True if the line was split; the cursor is then on the new line. }
procedure TApp.DoWrapAt(const s: string; idx: Integer);
var
  p, ind, newCol: Integer;
  rest, l1, l2: string;
begin
  { the last blank before the word being typed }
  p := idx - 1;
  while (p >= 1) and (not IsBlankCh(s[p])) do Dec(p);
  if (p < 1) or (FirstNonBlank(s) > p) then Exit;
  if LastNonBlank(Copy(s, 1, p)) = 0 then Exit;
  l1 := RTrim(Copy(s, 1, p));
  rest := Copy(s, p + 1, MaxInt);
  if optIndent then ind := IndentCol(s, TabStop) else ind := 0;
  newCol := ind + ColOfIdx(rest, idx - p, TabStop);
  l2 := Blanks(ind) + rest;
  SetCurText(l1);
  CD.InsertLine(CW.line + 1, l2);
  Inc(CW.line);
  CW.col := newCol;
end;

procedure TApp.TypeChar(const ch: string);
var
  s, closer: string;
  idx, pad, n, ci: Integer;
  c0: Char;
begin
  if (ch = #10) then begin DoReturn; Exit; end;
  s := CurText;
  { word wrap }
  if optWrap and (not pasting) and (CW.col >= rmargin) and (ch <> ' ') then begin
    idx := CurIdx(s, pad);
    if pad = 0 then DoWrapAt(s, idx);
    s := CurText;
  end;
  { C mode: a closing brace on an otherwise blank line steps back one indent }
  if (ch = '}') and optIndent and Info(CD).cmode and (LastNonBlank(s) = 0) and (CW.col >= ctab) and (not pasting) then
    Dec(CW.col, ctab);
  idx := CurIdx(s, pad);
  if pad > 0 then begin s := s + Blanks(pad); idx := Length(s) + 1; end;
  if optInsert or (idx > Length(s)) or (s[idx] = #9) then
    s := Copy(s, 1, idx - 1) + ch + Copy(s, idx, MaxInt)
  else begin
    n := CharLen(s, idx);
    s := Copy(s, 1, idx - 1) + ch + Copy(s, idx + n, MaxInt);
  end;
  closer := '';
  if optMatching and (not pasting) and (Length(ch) = 1) then begin
    c0 := ch[1];
    if c0 = '(' then closer := ')'
    else if c0 = '[' then closer := ']'
    else if c0 = '"' then closer := '"';
    if closer <> '' then s := Copy(s, 1, idx + Length(ch) - 1) + closer + Copy(s, idx + Length(ch), MaxInt);
  end;
  SetCurText(s);
  ci := idx + Length(ch);
  CW.col := ColOfIdx(s, ci, TabStop);
end;

procedure TApp.TypeText(const t: string);
var
  i, n: Integer;
begin
  i := 1;
  while i <= Length(t) do begin
    n := CharLen(t, i);
    TypeChar(Copy(t, i, n));
    Inc(i, n);
  end;
end;

procedure TApp.DoReturn;
var
  s, left, right, nt: string;
  idx, pad, ind: Integer;
  atEnd: Boolean;
begin
  s := CurText;
  ind := 0;
  if optIndent and (not pasting) then ind := IndentCol(s, TabStop);
  if (not optInsert) or (not optReturnSplit) then begin
    { overwrite mode: just go to the next line }
    if (not CD.LastLineKnown) or (CW.line < CD.LastLine) then MoveDown
    else begin
      CD.InsertLine(CW.line + 1, '');
      Inc(CW.line);
    end;
    CW.col := ind;
    Exit;
  end;
  idx := CurIdx(s, pad);
  if pad > 0 then begin left := s + Blanks(pad); right := ''; end
  else begin left := Copy(s, 1, idx - 1); right := Copy(s, idx, MaxInt); end;
  if optIndent and (not pasting) then begin
    if Info(CD).cmode and (Length(RTrim(left)) > 0) and (RTrim(left)[Length(RTrim(left))] = '{') then
      Inc(ind, ctab);
    right := LTrim(right);
    if LastNonBlank(left) = 0 then left := '';
  end;
  atEnd := right = '';
  if atEnd then nt := '' else nt := Blanks(ind) + right;
  { do not leave trailing blanks behind when a line is split in the middle of its text }
  if (not atEnd) and (pad = 0) then left := RTrim(left);
  SetCurText(left);
  CD.InsertLine(CW.line + 1, nt);
  Inc(CW.line);
  CW.col := ind;
end;

procedure TApp.DoBackspace;
var
  s, pl: string;
  idx, pad, ti, ocol: Integer;
begin
  if CW.col = 0 then begin
    if CW.line = 0 then Exit;
    pl := CD.Get(CW.line - 1);
    s := CurText;
    ocol := LineWidth(pl, TabStop);
    SetCurText('');
    CD.SetLine(CW.line - 1, pl + s);
    CD.DeleteLine(CW.line);
    Dec(CW.line);
    CW.col := ocol;
    Exit;
  end;
  s := CurText;
  idx := CurIdx(s, pad);
  if pad > 0 then begin Dec(CW.col); Exit; end;
  ti := IdxOfCol(s, CW.col - 1, TabStop, pad);
  if ti > Length(s) then begin Dec(CW.col); Exit; end;
  if optInsert then begin
    ocol := ColOfIdx(s, ti, TabStop);
    s := Copy(s, 1, ti - 1) + Copy(s, CharNext(s, ti), MaxInt);
    SetCurText(s);
    CW.col := ocol;
  end else begin
    if s[ti] <> #9 then begin
      s := Copy(s, 1, ti - 1) + ' ' + Copy(s, CharNext(s, ti), MaxInt);
      SetCurText(s);
    end;
    Dec(CW.col);
  end;
end;

procedure TApp.DoDelCh;
var
  s, nx: string;
  idx, pad: Integer;
begin
  s := CurText;
  idx := CurIdx(s, pad);
  if (pad > 0) or (idx > Length(s)) then begin
    if optDelJoin and (CD.Seek(CW.line + 1) = CW.line + 1) then begin
      nx := CD.Get(CW.line + 1);
      SetCurText(Copy(s, 1, idx - 1) + Blanks(pad) + nx);
      CD.DeleteLine(CW.line + 1);
    end;
    Exit;
  end;
  SetCurText(Copy(s, 1, idx - 1) + Copy(s, CharNext(s, idx), MaxInt));
end;

procedure TApp.DoTab(forward: Boolean);
var
  s: string;
  tw, nc, idx, pad, n, i, c0, k: Integer;
  above: string;
  p: Integer;
begin
  tw := ptab;
  if Info(CD).cmode and optIndent then tw := ctab;
  s := CurText;
  if forward then begin
    if optSmart and (CW.line > 0) then begin
      above := CD.Get(CW.line - 1);
      { next word start on the line above, to the right of the cursor }
      idx := IdxOfCol(above, CW.col, TabStop, pad);
      i := idx;
      if pad = 0 then begin
        while (i <= Length(above)) and (not IsBlankCh(above[i])) do Inc(i);
        while (i <= Length(above)) and IsBlankCh(above[i]) do Inc(i);
        if i <= Length(above) then nc := ColOfIdx(above, i, TabStop) else nc := CW.col;
      end else nc := CW.col;
    end else
      nc := (CW.col div tw + 1) * tw;
    if nc = CW.col then Exit;
    if optInsert then begin
      idx := CurIdx(s, pad);
      if (pad = 0) and (idx <= Length(s)) then begin
        n := nc - CW.col;
        if Info(CD).expand then s := Copy(s, 1, idx - 1) + Blanks(n) + Copy(s, idx, MaxInt)
        else s := Copy(s, 1, idx - 1) + #9 + Copy(s, idx, MaxInt);
        SetCurText(s);
      end;
    end;
    CW.col := nc;
  end else begin
    if optSmart and (CW.line > 0) then begin
      above := CD.Get(CW.line - 1);
      nc := 0;
      i := 1;
      while i <= Length(above) do begin
        while (i <= Length(above)) and IsBlankCh(above[i]) do Inc(i);
        if i > Length(above) then Break;
        k := ColOfIdx(above, i, TabStop);
        if k < CW.col then nc := k else Break;
        while (i <= Length(above)) and (not IsBlankCh(above[i])) do Inc(i);
      end;
    end else
      nc := ((CW.col - 1) div tw) * tw;
    if CW.col = 0 then Exit;
    if nc < 0 then nc := 0;
    if optInsert then begin
      { pull the text back by removing blanks directly left of the cursor }
      idx := CurIdx(s, pad);
      if pad = 0 then begin
        c0 := CW.col - nc;
        p := idx - 1;
        n := 0;
        while (p >= 1) and (n < c0) and (s[p] = ' ') do begin Dec(p); Inc(n); end;
        if n > 0 then begin
          s := Copy(s, 1, p) + Copy(s, idx, MaxInt);
          SetCurText(s);
          nc := CW.col - n;
        end;
      end;
    end;
    CW.col := nc;
  end;
end;

{ ===================================================================== words }

procedure TApp.DoWordRight;
var
  s: string;
  idx, pad: Integer;
begin
  s := CurText;
  idx := CurIdx(s, pad);
  if pad = 0 then begin
    while (idx <= Length(s)) and IsWordCh(s[idx]) do Inc(idx);
    while (idx <= Length(s)) and (not IsWordCh(s[idx])) do Inc(idx);
    if idx <= Length(s) then begin CW.col := ColOfIdx(s, idx, TabStop); Exit; end;
  end;
  { no further word on this line: first word of the next line }
  if CD.Seek(CW.line + 1) = CW.line + 1 then begin
    Inc(CW.line);
    s := CurText;
    idx := 1;
    while (idx <= Length(s)) and (not IsWordCh(s[idx])) do Inc(idx);
    if idx > Length(s) then idx := 1;
    CW.col := ColOfIdx(s, idx, TabStop);
  end;
end;

procedure TApp.DoWordLeft;
var
  s: string;
  idx, pad: Integer;
begin
  s := CurText;
  idx := CurIdx(s, pad);
  if pad > 0 then idx := Length(s) + 1;
  Dec(idx);
  while (idx >= 1) and (not IsWordCh(s[idx])) do Dec(idx);
  if idx >= 1 then begin
    while (idx >= 1) and IsWordCh(s[idx]) do Dec(idx);
    CW.col := ColOfIdx(s, idx + 1, TabStop);
    Exit;
  end;
  if CW.line > 0 then begin
    GoLine(CW.line - 1);
    s := CurText;
    idx := Length(s);
    while (idx >= 1) and (not IsWordCh(s[idx])) do Dec(idx);
    while (idx >= 1) and IsWordCh(s[idx]) do Dec(idx);
    CW.col := ColOfIdx(s, idx + 1, TabStop);
  end else
    CW.col := 0;
end;

procedure TApp.DoDelRtWord;
var
  s: string;
  idx, pad, j: Integer;
begin
  s := CurText;
  idx := CurIdx(s, pad);
  if (pad > 0) or (idx > Length(s)) then begin DoDelCh; Exit; end;
  j := idx;
  while (j <= Length(s)) and IsWordCh(s[j]) do Inc(j);
  if j = idx then
    while (j <= Length(s)) and (not IsWordCh(s[j])) and (not IsBlankCh(s[j])) do Inc(j);
  if optDelWs then
    while (j <= Length(s)) and IsBlankCh(s[j]) do Inc(j);
  KillText(kkFrag, Copy(s, idx, j - idx));
  SetCurText(Copy(s, 1, idx - 1) + Copy(s, j, MaxInt));
end;

procedure TApp.DoDelLtWord;
var
  s: string;
  idx, pad, j: Integer;
begin
  if CW.col = 0 then begin DoBackspace; Exit; end;
  s := CurText;
  idx := CurIdx(s, pad);
  if pad > 0 then begin
    { beyond the text: just move left over the blank space }
    CW.col := Length(s) + 0;
    CW.col := LineWidth(s, TabStop);
    Exit;
  end;
  j := idx - 1;
  while (j >= 1) and IsBlankCh(s[j]) do Dec(j);
  if (j >= 1) and IsWordCh(s[j]) then
    while (j >= 1) and IsWordCh(s[j]) do Dec(j)
  else
    while (j >= 1) and (not IsWordCh(s[j])) and (not IsBlankCh(s[j])) do Dec(j);
  Inc(j);
  SetCurText(Copy(s, 1, j - 1) + Copy(s, idx, MaxInt));
  CW.col := ColOfIdx(s, j, TabStop);
end;

{ ===================================================================== line commands }

procedure TApp.DoJoinLine;
var
  s, nx: string;
  idx, pad, lnb: Integer;
begin
  if CD.Seek(CW.line + 1) <> CW.line + 1 then Exit;
  s := CurText;
  nx := CD.Get(CW.line + 1);
  idx := CurIdx(s, pad);
  lnb := LastNonBlank(s);
  if LastNonBlank(nx) = 0 then begin
    CD.DeleteLine(CW.line + 1);
    Exit;
  end;
  if (pad = 0) and (idx <= lnb) then
    SetCurText(Copy(s, 1, lnb) + nx)
  else
    SetCurText(Copy(s, 1, idx - 1) + Blanks(pad) + nx);
  CD.DeleteLine(CW.line + 1);
end;

procedure TApp.DoSplitLine;
var
  s: string;
  idx, pad: Integer;
begin
  s := CurText;
  idx := CurIdx(s, pad);
  if pad > 0 then begin
    CD.InsertLine(CW.line + 1, '');
    Exit;
  end;
  SetCurText(Copy(s, 1, idx - 1));
  CD.InsertLine(CW.line + 1, Copy(s, idx, MaxInt));
end;

procedure TApp.DoAlign;
var
  s, a: string;
  ind: Integer;
begin
  if CW.line = 0 then begin MoveDown; Exit; end;
  a := CD.Get(CW.line - 1);
  ind := IndentCol(a, TabStop);
  s := LTrim(CurText);
  if (s <> '') and (LastNonBlank(a) > 0) then SetCurText(Blanks(ind) + s);
  MoveDown;
end;

procedure TApp.DoGetPrev;
var
  a: string;
  idx, pad: Integer;
begin
  if CW.line = 0 then Exit;
  a := CD.Get(CW.line - 1);
  idx := IdxOfCol(a, CW.col, TabStop, pad);
  if (pad > 0) or (idx > Length(a)) then TypeChar(' ')
  else begin
    if a[idx] = #9 then TypeChar(' ') else TypeChar(Copy(a, idx, CharLen(a, idx)));
  end;
end;

procedure TApp.DoLiteral;
var
  k: TKey;
  ch: string;
begin
  Msg('Literal: press a key');
  Refresh;
  repeat k := GetKey; until k.code <> kcNone;
  msgText := '';
  ch := '';
  case k.code of
    kcChar: begin
      if mCtrl in k.mods then begin
        if (Length(k.ch) = 1) and (k.ch[1] in ['a'..'z']) then ch := Chr(Ord(k.ch[1]) - 96)
        else if k.ch = '[' then ch := #27
        else if k.ch = '\' then ch := #28
        else if k.ch = ']' then ch := #29
        else if k.ch = '^' then ch := #30
        else if k.ch = '_' then ch := #31;
      end else ch := k.ch;
    end;
    kcEnter: ch := #13;
    kcTab: ch := #9;
    kcEsc: ch := #27;
    kcBack: ch := #127;
  end;
  if ch = '' then Exit;
  if ch = #10 then begin DoSplitLine; Exit; end;
  TypeChar(ch);
end;

procedure TApp.DoUnKill;
var
  inf: TDocInfo;
  e: TKillEntry;
  eL: Int64;
  eC: Integer;
begin
  inf := Info(CD);
  if inf.kill.Count = 0 then begin Msg('Kill buffer is empty'); Exit; end;
  e := TKillEntry(inf.kill[inf.kill.Count - 1]);
  inf.kill.Delete(inf.kill.Count - 1);
  case e.kind of
    kkLine: begin
      CD.InsertLine(CW.line, e.scrap.lines[0]);
      Dec(CW.line);      { the cursor stays on the restored line }
    end;
    kkFrag: InsertScrap(CD, e.scrap, CW.line, CW.col, False, eL, eC);
    kkBlock: PasteScrap(e.scrap, False);
  end;
  e.Free;
end;

procedure TApp.DoUndoLine;
begin
  if CW.undoValid and (CW.undoLine = CW.line) then begin
    CD.SetLine(CW.line, CW.undoText);
    CW.undoValid := False;
    CW.col := 0;
  end else
    Msg('Nothing to undo');
end;

{ Reformat from the cursor line to the next blank line. }
procedure TApp.DoWrapPara;
var
  first, last, ln, i: Int64;
  words: TStringList;
  s, w2, cur2: string;
  firstInd, ind, k: Integer;
  outLines: TStringList;
  p: Integer;
begin
  first := CW.line;
  last := first;
  CD.Seek(first);
  { the paragraph: from the cursor line up to (not including) the next blank line }
  while True do begin
    if CD.Seek(last + 1) <> last + 1 then Break;
    if LastNonBlank(CD.Get(last + 1)) = 0 then Break;
    Inc(last);
  end;
  if LastNonBlank(CD.Get(first)) = 0 then begin MoveDown; Exit; end;
  CD.Seek(first);
  firstInd := IndentCol(CD.Get(first), TabStop);
  if optIndent and (last > first) then ind := IndentCol(CD.Get(first + 1), TabStop)
  else if optIndent then ind := firstInd
  else ind := 0;
  words := TStringList.Create;
  outLines := TStringList.Create;
  try
    for ln := first to last do begin
      CD.Seek(ln);
      s := CD.Get(ln);
      p := 1;
      while p <= Length(s) do begin
        while (p <= Length(s)) and IsBlankCh(s[p]) do Inc(p);
        k := p;
        while (k <= Length(s)) and (not IsBlankCh(s[k])) do Inc(k);
        if k > p then words.Add(Copy(s, p, k - p));
        p := k;
      end;
    end;
    cur2 := '';
    for i := 0 to words.Count - 1 do begin
      w2 := words[i];
      if cur2 = '' then begin
        if outLines.Count = 0 then cur2 := Blanks(firstInd) + w2 else cur2 := Blanks(ind) + w2;
      end else if Length(cur2) + 1 + Length(w2) <= rmargin then
        cur2 := cur2 + ' ' + w2
      else begin
        outLines.Add(cur2);
        cur2 := Blanks(ind) + w2;
      end;
    end;
    if cur2 <> '' then outLines.Add(cur2);
    { replace the old lines with the new ones }
    CD.Seek(first);
    for ln := first to last do begin CD.Seek(first); CD.DeleteLine(first); end;
    for i := 0 to outLines.Count - 1 do begin
      CD.Seek(first + i);
      CD.InsertLine(first + i, outLines[i]);
    end;
    CW.line := first + outLines.Count;
    CW.line := CD.Seek(CW.line);
    CW.col := 0;
  finally
    words.Free;
    outLines.Free;
  end;
end;

{ Find the bracket matching the one under the cursor. }
procedure TApp.DoMatch;
var
  s: string;
  idx, pad, depth, dirn, count: Integer;
  c, o: Char;
  ln: Int64;
  i: Integer;
  k: TKey;
begin
  s := CurText;
  idx := CurIdx(s, pad);
  if (pad > 0) or (idx > Length(s)) then begin Msg('Not on a bracket'); Exit; end;
  c := s[idx];
  case c of
    '(': begin o := ')'; dirn := 1; end;
    '[': begin o := ']'; dirn := 1; end;
    '{': begin o := '}'; dirn := 1; end;
    ')': begin o := '('; dirn := -1; end;
    ']': begin o := '['; dirn := -1; end;
    '}': begin o := '{'; dirn := -1; end;
  else
    Msg('Not on a bracket');
    Exit;
  end;
  depth := 0;
  ln := CW.line;
  i := idx + dirn;
  count := 0;
  SavePrev;
  while True do begin
    while (i >= 1) and (i <= Length(s)) do begin
      if s[i] = c then Inc(depth)
      else if s[i] = o then begin
        if depth = 0 then begin
          CW.line := ln;
          CW.col := ColOfIdx(s, i, TabStop);
          Exit;
        end;
        Dec(depth);
      end;
      Inc(i, dirn);
    end;
    ln := ln + dirn;
    if ln < 0 then Break;
    if CD.Seek(ln) <> ln then Break;
    s := CD.Get(ln);
    if dirn > 0 then i := 1 else i := Length(s);
    Inc(count);
    if (count and 4095) = 0 then
      if KeyRead(k) and (k.code = kcEsc) then begin Msg('Aborted'); GoLine(CW.line); Exit; end;
  end;
  GoLine(CW.line);
  Msg('No matching bracket');
end;

{ Box drawing: the arrow keys leave lines of box characters behind. A cell's connections are kept as
  bits (1 up, 2 right, 4 down, 8 left); the window remembers what the cell it is standing on held
  before we drew on it, so that turning a corner gives a corner and crossing a line gives a cross. }
procedure TApp.DoBoxMove(dir: Integer);
const
  BoxCh: array[0..15] of string = (
    ' ', '│', '─', '└', '│', '│', '┌', '├', '─', '┘', '─', '┴', '┐', '┤', '┬', '┼');
var
  m, back, orig, prior: Integer;
  nl: Int64;
  nc: Integer;

  function DirBit(d: Integer): Integer;
  begin
    Result := 1 shl (d - 1);
  end;

  function MaskOf(const ch: string): Integer;
  begin
    if ch = '─' then Result := 10
    else if ch = '│' then Result := 5
    else if ch = '┌' then Result := 6
    else if ch = '┐' then Result := 12
    else if ch = '└' then Result := 3
    else if ch = '┘' then Result := 9
    else if ch = '├' then Result := 7
    else if ch = '┤' then Result := 13
    else if ch = '┬' then Result := 14
    else if ch = '┴' then Result := 11
    else if ch = '┼' then Result := 15
    else Result := 0;
  end;

  procedure PutBox(line: Int64; col, mask: Integer);
  var
    t: string;
    ix, pd: Integer;
  begin
    t := CD.Get(line);
    ix := IdxOfCol(t, col, TabStop, pd);
    if pd > 0 then begin t := t + Blanks(pd); ix := Length(t) + 1; end;
    if ix > Length(t) then t := t + BoxCh[mask]
    else t := Copy(t, 1, ix - 1) + BoxCh[mask] + Copy(t, CharNext(t, ix), MaxInt);
    CD.SetLine(line, t);
  end;

  function GetMask(line: Int64; col: Integer): Integer;
  var
    t: string;
    ix, pd: Integer;
  begin
    t := CD.Get(line);
    ix := IdxOfCol(t, col, TabStop, pd);
    if (pd > 0) or (ix > Length(t)) then Exit(0);
    Result := MaskOf(Copy(t, ix, CharLen(t, ix)));
  end;

begin
  nl := CW.line;
  nc := CW.col;
  case dir of
    1: Dec(nl);
    2: Inc(nc);
    3: Inc(nl);
    4: Dec(nc);
  end;
  if (nl < 0) or (nc < 0) then Exit;
  if nl <> CW.line then begin
    if CD.Seek(nl) <> nl then begin
      if dir = 3 then CD.InsertLine(nl, '') else Exit;
    end;
  end;
  { where we are standing: either the cell we arrived at by the last box move, or a fresh one }
  if (CW.boxDir <> 0) and (CW.boxLine = CW.line) and (CW.boxCol = CW.col) then begin
    prior := CW.boxMask;
    back := DirBit(((CW.boxDir + 1) mod 4) + 1);
  end else begin
    prior := GetMask(CW.line, CW.col);
    back := 0;
  end;
  orig := prior or back or DirBit(dir);
  PutBox(CW.line, CW.col, orig);
  { the cell we step onto connects back towards where we came from }
  prior := GetMask(nl, nc);
  m := prior or DirBit(((dir + 1) mod 4) + 1);
  PutBox(nl, nc, m);
  CW.line := nl;
  CW.col := nc;
  CW.boxDir := dir;
  CW.boxMask := prior;
  CW.boxLine := nl;
  CW.boxCol := nc;
end;

{ ===================================================================== cursor motion }

procedure TApp.MoveUp;
begin
  if CW.line > 0 then GoLine(CW.line - 1);
end;

procedure TApp.MoveDown;
var
  n: Int64;
begin
  n := CD.Seek(CW.line + 1);
  if n = CW.line + 1 then CW.line := n;
  GoLine(CW.line);
end;

procedure TApp.MovePage(dir: Integer; half: Boolean);
var
  n: Integer;
  target: Int64;
begin
  n := CW.h - 2;
  if half then n := n div 2;
  if n < 1 then n := 1;
  SavePrev;
  if dir > 0 then begin
    target := CD.Seek(CW.line + n);
    if target > CW.line then begin
      CW.top := CW.top + (target - CW.line);
      CW.line := target;
    end;
  end else begin
    if CW.line = 0 then Exit;
    target := CW.line - n;
    if target < 0 then target := 0;
    CW.top := CW.top - (CW.line - target);
    if CW.top < 0 then CW.top := 0;
    CW.line := target;
  end;
  GoLine(CW.line);
end;

procedure TApp.ScrollView(dir: Integer; moveCursor: Boolean);
var
  rows: Integer;
  n: Int64;
begin
  rows := CW.h - 1;
  if dir < 0 then begin
    { text moves down: view goes towards the start of the file }
    if CW.top = 0 then Exit;
    Dec(CW.top);
    if moveCursor then begin if CW.line > 0 then Dec(CW.line); end
    else if CW.line > CW.top + rows - 1 then CW.line := CW.top + rows - 1;
  end else begin
    n := CD.Seek(CW.top + rows);      { the line that would scroll into view }
    if n < CW.top + rows then Exit; { at the end of the file }
    Inc(CW.top);
    if moveCursor then begin
      n := CD.Seek(CW.line + 1);
      if n = CW.line + 1 then CW.line := n;
    end else if CW.line < CW.top then CW.line := CW.top;
  end;
  GoLine(CW.line);
end;

procedure TApp.PlaceScreen(mode: Integer);
var
  rows: Integer;
begin
  rows := CW.h - 1;
  case mode of
    0: CW.top := CW.line;
    1: CW.top := CW.line - rows div 2;
    2: CW.top := CW.line - rows + 1;
  end;
  if CW.top < 0 then CW.top := 0;
end;

procedure TApp.DoGotoLine;
var
  s: string;
  n: Integer;
begin
  if not Prompt('line number: <Esc = abort>', '', s) then Exit;
  n := StrToIntDef(Trim(s), 0);
  if n < 1 then begin Msg('Bad line number'); Exit; end;
  SavePrev;
  GoLine(n - 1);
  if CW.line < n - 1 then Msg('Past the end of the file');
end;

procedure TApp.DoBegEndFile(atEnd: Boolean);
begin
  SavePrev;
  if atEnd then begin
    GoLine(High(Int32));
    CW.col := EndCol(CurText);
  end else begin
    GoLine(0);
    CW.col := 0;
    CW.top := 0;
  end;
end;

{ Center the cursor line between column 1 and the right margin. }
procedure TApp.DoCenterLine;
var
  t: string;
  pad: Integer;
begin
  t := Trim(CurText);
  if t = '' then Exit;
  pad := (rmargin - Utf8Len(t)) div 2;
  if pad < 0 then pad := 0;
  SetCurText(Blanks(pad) + t);
  CW.col := 0;
end;

{ Pipe the marked block through a shell command and put the output in its place (JOE's ^K /). }
procedure TApp.DoFilterBlock;
var
  l1, l2: Int64;
  c1, c2, i, rc: Integer;
  cmd, tin, tout, content: string;
  sc, res: TScrap;
  f: TFileStream;
  p, q: Integer;
  wasAll: Boolean;
  kind: TBlockKind;
begin
  if not BlockRange(l1, c1, l2, c2) then begin Msg('No block marked'); Exit; end;
  if bDoc <> CD then begin Msg('The block is in another file'); Exit; end;
  if not Prompt('Filter block through command: <Esc = abort>', '', cmd) then Exit;
  if Trim(cmd) = '' then Exit;
  kind := bKind;
  sc := ExtractBlock(CD, kind, l1, c1, l2, c2);
  tin := GetTempFileName('', 'mkedit-filter-');
  tout := tin + '.out';
  res := TScrap.Create;
  try
    try
      f := TFileStream.Create(tin, fmCreate);
      try
        for i := 0 to sc.lines.Count - 1 do begin
          content := sc.lines[i] + #10;
          f.WriteBuffer(content[1], Length(content));
        end;
      finally
        f.Free;
      end;
    except
      on E: Exception do begin Msg('Cannot write a temporary file'); Exit; end;
    end;
    rc := fpSystem('(' + cmd + ') < "' + tin + '" > "' + tout + '" 2>&1');
    if (rc <> 0) or (not FileExists(tout)) then begin
      Msg('The command failed (status ' + IntToStr(rc) + '); the block is unchanged');
      Exit;
    end;
    f := TFileStream.Create(tout, fmOpenRead);
    try
      SetLength(content, f.Size);
      if f.Size > 0 then f.ReadBuffer(content[1], f.Size);
    finally
      f.Free;
    end;
    res.kind := kind;
    p := 1;
    while p <= Length(content) do begin
      q := p;
      while (q <= Length(content)) and (content[q] <> #10) do Inc(q);
      res.lines.Add(Copy(content, p, q - p));
      p := q + 1;
    end;
    if (kind = bkStream) and (res.lines.Count = 0) then res.lines.Add('');
    CD.Seek(l2);
    wasAll := (kind = bkLine) and (l1 = 0) and CD.LastLineKnown and (l2 = CD.LastLine);
    RemoveBlock(CD, kind, l1, c1, l2, c2);
    if kind = bkLine then begin
      for i := 0 to res.lines.Count - 1 do begin
        CD.Seek(l1 + i);
        CD.InsertLine(l1 + i, res.lines[i]);
      end;
      if wasAll and (res.lines.Count > 0) then begin
        { the whole file was replaced: drop the empty line the removal left behind }
        CD.Seek(l1 + res.lines.Count);
        if CD.Get(l1 + res.lines.Count) = '' then CD.DeleteLine(l1 + res.lines.Count);
      end;
    end else begin
      InsertScrap(CD, res, l1, c1, False, l2, i);
    end;
    ClearBlock;
    CW.line := l1;
    CW.col := 0;
    GoLine(CW.line);
    Msg('Block filtered through ' + cmd);
  finally
    DeleteFile(tin);
    DeleteFile(tout);
    sc.Free;
    res.Free;
  end;
end;

{ ===================================================================== search }

function AsciiLower(const s: string): string;
var
  i: Integer;
begin
  Result := s;
  for i := 1 to Length(Result) do
    if (Result[i] >= 'A') and (Result[i] <= 'Z') then Inc(Result[i], 32);
end;

function WordBoundaryOK(const s: string; p, len: Integer): Boolean;
begin
  Result := True;
  if (p > 1) and IsWordCh(s[p - 1]) then Result := False;
  if (p + len <= Length(s)) and IsWordCh(s[p + len]) then Result := False;
end;

{ A match of lp in ls (both already case-folded if wanted) starting at or after `from` (forward) or
  strictly before `limit` (backward). Returns the 1-based index or 0. }
function MatchInLine(const ls, lp: string; from, limit: Integer; fwd, words: Boolean): Integer;
var
  p, last: Integer;
begin
  Result := 0;
  if (lp = '') or (Length(ls) < Length(lp)) then Exit;
  if fwd then begin
    p := from;
    if p < 1 then p := 1;
    while p <= Length(ls) - Length(lp) + 1 do begin
      p := PosEx(lp, ls, p);
      if p = 0 then Exit;
      if (not words) or WordBoundaryOK(ls, p, Length(lp)) then Exit(p);
      Inc(p);
    end;
  end else begin
    last := limit - 1;
    if last > Length(ls) - Length(lp) + 1 then last := Length(ls) - Length(lp) + 1;
    for p := last downto 1 do
      if (CompareByte(ls[p], lp[1], Length(lp)) = 0) and ((not words) or WordBoundaryOK(ls, p, Length(lp))) then
        Exit(p);
  end;
end;

{ Search from the cursor. fromCursor: skip a match that starts exactly at the cursor (Find again). }
function TApp.FindText(const pat, opts: string; fromCursor: Boolean; out ln: Int64; out idx: Integer): Boolean;
var
  o, s, lp: string;
  fwd, ic, ww: Boolean;
  cidx, pad, from, limit, steps: Integer;
  k: TKey;
  n: Int64;
begin
  Result := False;
  o := UpperCase(opts);
  fwd := Pos('B', o) = 0;
  ic := Pos('I', o) > 0;
  ww := Pos('W', o) > 0;
  if ic then lp := AsciiLower(pat) else lp := pat;
  ln := CW.line;
  s := CurText;
  cidx := CurIdx(s, pad);
  if pad > 0 then cidx := Length(s) + 1;
  if fwd then begin
    from := cidx;
    if fromCursor and (cidx <= Length(s)) then from := CharNext(s, cidx);
    if fromCursor and (cidx > Length(s)) then from := Length(s) + 2;
  end else begin
    limit := cidx;
  end;
  steps := 0;
  while True do begin
    if ic then idx := MatchInLine(AsciiLower(s), lp, from, limit, fwd, ww)
    else idx := MatchInLine(s, lp, from, limit, fwd, ww);
    if idx > 0 then Exit(True);
    if fwd then begin
      n := ln + 1;
      if CD.Seek(n) <> n then Break;
      ln := n;
      from := 1;
    end else begin
      if ln = 0 then Break;
      n := ln - 1;
      CD.Seek(n);
      ln := n;
      limit := MaxInt;
    end;
    s := CD.Get(ln);
    Inc(steps);
    if (steps and 2047) = 0 then
      if KeyRead(k) and (k.code = kcEsc) then begin Msg('Search aborted'); Break; end;
  end;
  Result := False;
end;

var
  GLastReplace: Boolean = False;

procedure TApp.DoFind(replace: Boolean);
var
  pat, repl, o, ttl: string;
  origLine: Int64;
  origCol: Integer;
  ln: Int64;
  idx, count, pad, ci: Integer;
  s, ns: string;
  global, noask, quit, found: Boolean;
  c: Char;
  fwd: Boolean;
begin
  if not Prompt('Search for: <Esc = Abort>', fFind, pat) then Exit;
  if pat = '' then Exit;
  repl := '';
  if replace then begin
    if not Prompt('Change to: <Esc = Abort>', fRepl, repl) then Exit;
    ttl := 'Options [IWBN] (Ignore, Words, Backward, No Ask) <Esc = Abort>';
  end else
    ttl := 'Options [IWB] (Ignore, Words, Backward) <Esc = Abort>';
  if replace then begin
    if not Prompt(ttl, fOptsR, o) then Exit;
    fOptsR := UpperCase(o);
  end else begin
    if not Prompt(ttl, fOptsF, o) then Exit;
    fOptsF := UpperCase(o);
  end;
  fFind := pat;
  fRepl := repl;
  fOpts := UpperCase(o);
  GLastReplace := replace;
  origLine := CW.line;
  origCol := CW.col;
  fwd := Pos('B', fOpts) = 0;
  if not replace then begin
    if FindText(pat, fOpts, False, ln, idx) then begin
      SavePrev;
      GoLine(ln);
      CW.col := ColOfIdx(CD.Get(ln), idx, TabStop);
      hlLine := ln; hlCol := CW.col; hlLen := ColOfIdx(CD.Get(ln), idx + Length(pat), TabStop) - CW.col;
    end else begin
      GoLine(origLine);
      CW.col := origCol;
      if msgText = '' then Msg('Not found');
    end;
    Exit;
  end;
  { find and replace }
  count := 0;
  noask := Pos('N', fOpts) > 0;
  global := noask;
  quit := False;
  SavePrev;
  while not quit do begin
    found := FindText(pat, fOpts, False, ln, idx);
    if not found then Break;
    GoLine(ln);
    s := CurText;
    CW.col := ColOfIdx(s, idx, TabStop);
    if not global then begin
      hlLine := ln; hlCol := CW.col; hlLen := ColOfIdx(s, idx + Length(pat), TabStop) - CW.col;
      c := AskKey('Replace (Yes/No/Only/Global/Quit):', 'YNOGQ');
      case c of
        'Y': hlLen := 0;
        'N': begin
          hlLen := 0;
          if fwd then CW.col := ColOfIdx(s, CharNext(s, idx), TabStop);
          Continue;
        end;
        'O': quit := True;
        'G': global := True;
      else
        Break;
      end;
    end;
    ns := Copy(s, 1, idx - 1) + repl + Copy(s, idx + Length(pat), MaxInt);
    SetCurText(ns);
    Inc(count);
    if fwd then CW.col := ColOfIdx(ns, idx + Length(repl), TabStop)
    else CW.col := ColOfIdx(ns, idx, TabStop);
  end;
  if count = 0 then begin
    if msgText = '' then Msg('Not found');
    if not found then begin GoLine(origLine); CW.col := origCol; end;
  end else
    Msg(IntToStr(count) + ' replaced');
end;

procedure TApp.DoRepeatFind;
var
  ln: Int64;
  idx, count: Integer;
  s, ns: string;
  fwd: Boolean;
begin
  if fFind = '' then begin Msg('Nothing to repeat'); Exit; end;
  fwd := Pos('B', fOpts) = 0;
  if GLastReplace then begin
    count := 0;
    while FindText(fFind, fOpts, False, ln, idx) do begin
      GoLine(ln);
      s := CurText;
      ns := Copy(s, 1, idx - 1) + fRepl + Copy(s, idx + Length(fFind), MaxInt);
      SetCurText(ns);
      Inc(count);
      if fwd then CW.col := ColOfIdx(ns, idx + Length(fRepl), TabStop) else CW.col := ColOfIdx(ns, idx, TabStop);
      if Pos('N', fOpts) = 0 then Break;     { one at a time unless "no ask" }
    end;
    if count = 0 then Msg('Not found');
    Exit;
  end;
  if FindText(fFind, fOpts, True, ln, idx) then begin
    SavePrev;
    GoLine(ln);
    CW.col := ColOfIdx(CD.Get(ln), idx, TabStop);
    hlLine := ln; hlCol := CW.col; hlLen := ColOfIdx(CD.Get(ln), idx + Length(fFind), TabStop) - CW.col;
  end else if msgText = '' then Msg('Not found');
end;

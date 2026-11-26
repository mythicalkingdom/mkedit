{ ===================================================================== undo / redo }

procedure TApp.DoUndoRedo(redo: Boolean);
var
  l: Int64;
  c: Integer;
  ok: Boolean;
begin
  CW.undoValid := False;
  if redo then ok := CD.Redo(l, c) else ok := CD.Undo(l, c);
  if not ok then begin
    if redo then Msg('Nothing to redo') else Msg('Nothing to undo');
    Exit;
  end;
  GoLine(l);
  CW.col := c;
  if redo then Msg('Redone') else Msg('Undone');
end;

{ ===================================================================== programmer tools }
{ Build and grep write their output into a scratch document ("* Build Log *"); lines that look like
  "file:line:col: message", "file(line,col) message" or Python's File "x", line N are errors that
  NextError / PrevError jump to, as in JOE. }

function QuoteSh(const s: string): string;
begin
  Result := '''' + StringReplace(s, '''', '''\''''', [rfReplaceAll]) + '''';
end;

{ Is this log line an error location? }
function ParseErr(const s: string; out f: string; out ln: Int64; out col: Integer): Boolean;
var
  i, j, k, p: Integer;
  num: string;

  function Digits(from: Integer; out upto: Integer): string;
  begin
    upto := from;
    while (upto <= Length(s)) and (s[upto] in ['0'..'9']) do Inc(upto);
    Result := Copy(s, from, upto - from);
  end;

begin
  Result := False;
  f := ''; ln := 0; col := 0;
  { Python: File "name", line N }
  p := Pos('File "', s);
  if p > 0 then begin
    i := p + 6;
    j := i;
    while (j <= Length(s)) and (s[j] <> '"') do Inc(j);
    if (j <= Length(s)) and (Copy(s, j, 8) = '", line ') then begin
      num := Digits(j + 8, k);
      if num <> '' then begin f := Copy(s, i, j - i); ln := StrToInt64(num); Exit(True); end;
    end;
  end;
  { Free Pascal / Delphi: name.pas(12,5) Error: ... }
  p := Pos('(', s);
  if p > 1 then begin
    i := p - 1;
    while (i >= 1) and (s[i] <> ' ') do Dec(i);
    f := Copy(s, i + 1, p - i - 1);
    if (f <> '') and ((Pos('.', f) > 0) or (Pos('/', f) > 0)) then begin
      num := Digits(p + 1, k);
      if (num <> '') and (k <= Length(s)) and (s[k] in [',', ')']) then begin
        ln := StrToInt64(num);
        if s[k] = ',' then begin
          num := Digits(k + 1, j);
          if num <> '' then col := StrToInt(num);
        end;
        Exit(True);
      end;
    end;
  end;
  { gcc, grep -n, rustc, go ...: name:12:5: message  or  name:12:text }
  p := Pos(':', s);
  if (p > 1) then begin
    f := Copy(s, 1, p - 1);
    if Pos(' ', f) = 0 then begin
      num := Digits(p + 1, k);
      if (num <> '') and (k <= Length(s) + 1) and ((k > Length(s)) or (s[k] = ':')) then begin
        ln := StrToInt64(num);
        if (k <= Length(s)) then begin
          num := Digits(k + 1, j);
          if (num <> '') and (j <= Length(s)) and (s[j] = ':') then col := StrToInt(num);
        end;
        Exit(True);
      end;
    end;
  end;
  f := '';
end;

function TApp.WordUnderCursor: string;
var
  s: string;
  idx, pad, a, b: Integer;
begin
  Result := '';
  s := CurText;
  idx := CurIdx(s, pad);
  if (pad > 0) or (idx > Length(s)) then Exit;
  a := idx;
  while (a > 1) and IsWordCh(s[a - 1]) do Dec(a);
  b := idx;
  while (b <= Length(s)) and IsWordCh(s[b]) do Inc(b);
  Result := Copy(s, a, b - a);
end;

{ The scratch document behind slot, created when needed and placed after the current file in the ring. }
function TApp.LogDoc(var slot: TDoc; const title: string): TDoc;
begin
  if (slot <> nil) and (DocIndex(slot) >= 0) then Exit(slot);
  slot := NewDoc('');
  slot.Name := title;
  slot.NewFile := False;
  Info(slot).scratch := True;
  docs.Insert(DocIndex(CD) + 1, slot);
  Result := slot;
end;

procedure TApp.FillLog(d: TDoc; lines: TStrings);
var
  i: Integer;
  n: Int64;
begin
  repeat
    n := d.Seek(High(Int32));
    if n = 0 then Break;
    d.DeleteLine(n);
  until False;
  d.Seek(0);
  if lines.Count = 0 then d.SetLine(0, '') else d.SetLine(0, lines[0]);
  for i := 1 to lines.Count - 1 do begin
    d.Seek(i - 1);
    d.InsertLine(i, lines[i]);
  end;
  d.ClearUndo;
  d.Modified := False;
  d.MarkSaved;
end;

{ Make sure some window shows d without taking the focus away from the one being edited. }
procedure TApp.ShowLog(d: TDoc);
var
  i, shown: Integer;
begin
  for i := 0 to nwins - 1 do
    if wins[i].doc = d then begin
      wins[i].line := 0; wins[i].top := 0;
      Exit;
    end;
  zoomed := False;
  if nwins = 1 then begin
    WinSplit;
    if nwins = 1 then Exit;
    shown := cur;
    ShowDoc(wins[shown], d);
    cur := shown - 1;
  end else begin
    shown := (cur + 1) mod nwins;
    ShowDoc(wins[shown], d);
  end;
end;

procedure TApp.JumpToError(const f: string; ln: Int64; col: Integer);
var
  full: string;
  i, t: Integer;
begin
  if (f <> '') and (f[1] = '/') then full := f
  else full := IncludeTrailingPathDelimiter(buildCwd) + f;
  full := ExpandFileName(full);
  if not FileExists(full) then begin Msg('Cannot find ' + full); Exit; end;
  t := cur;
  if CW.doc = errDoc then begin
    for i := 0 to nwins - 1 do
      if wins[i].doc <> errDoc then begin t := i; Break; end;
  end;
  cur := t;
  OpenFile(full);
  SavePrev;
  GoLine(ln - 1);
  if col > 0 then CW.col := col - 1 else CW.col := 0;
end;

{ dir = 1 next, -1 previous }
procedure TApp.DoNextError(dir: Integer);
var
  ln: Int64;
  f, t: string;
  l: Int64;
  c, i, rows: Integer;
begin
  if (errDoc = nil) or (DocIndex(errDoc) < 0) then begin
    Msg('No error list: run Compile or Grep first');
    Exit;
  end;
  ln := errLine + dir;
  if ln < 0 then ln := 0;
  while (ln >= 0) and (errDoc.Seek(ln) = ln) do begin
    t := errDoc.Get(ln);
    if ParseErr(t, f, l, c) then begin
      errLine := ln;
      { show the message's line in the log window }
      for i := 0 to nwins - 1 do
        if wins[i].doc = errDoc then begin
          rows := wins[i].h - 1;
          wins[i].line := ln;
          if (ln < wins[i].top) or (ln >= wins[i].top + rows) then wins[i].top := Max(0, ln - rows div 2);
        end;
      JumpToError(f, l, c);
      Msg(Trim(t));
      Exit;
    end;
    ln := ln + dir;
  end;
  Msg('No more errors');
end;

procedure TApp.RunToLog(const cmd: string; var slot: TDoc; const title: string; out status: Integer);
var
  tmp: string;
  sl: TStringList;
  d: TDoc;
begin
  buildCwd := GetCurrentDir;
  tmp := GetTempFileName('', 'mkedit-run-');
  Msg('Running: ' + cmd);
  Refresh;
  status := fpSystem('(' + cmd + ') > "' + tmp + '" 2>&1 < /dev/null');
  sl := TStringList.Create;
  try
    try
      if FileExists(tmp) then sl.LoadFromFile(tmp);
    except
    end;
    if sl.Count > 50000 then begin
      while sl.Count > 50000 do sl.Delete(sl.Count - 1);
      sl.Add('[output truncated]');
    end;
    sl.Add('[exit status ' + IntToStr(status) + ']');
    d := LogDoc(slot, title);
    FillLog(d, sl);
    ShowLog(d);
    errDoc := d;
    errLine := -1;
  finally
    sl.Free;
    DeleteFile(tmp);
  end;
end;

procedure TApp.DoCompile;
var
  cmd: string;
  i, status: Integer;
  d: TDoc;
  c: Char;
  anyMod: Boolean;
begin
  if not Prompt('Build command: <Esc = abort>', buildCmd, cmd) then Exit;
  cmd := Trim(cmd);
  if cmd = '' then Exit;
  buildCmd := cmd;
  anyMod := False;
  for i := 0 to docs.Count - 1 do
    if TDoc(docs[i]).Modified and (not Info(TDoc(docs[i])).scratch) then anyMod := True;
  if anyMod then begin
    c := AskKey('Save modified files before building? (Y/N, Esc = cancel)', 'YN');
    if c = #27 then Exit;
    if c = 'Y' then
      for i := 0 to docs.Count - 1 do begin
        d := TDoc(docs[i]);
        if d.Modified and (not Info(d).scratch) and (d.Name <> '') then
          if not SaveDoc(d) then Exit;
      end;
  end;
  RunToLog(cmd, buildDoc, '* Build Log *', status);
  errLine := -1;
  DoNextError(1);
  if msgText = 'No more errors' then begin
    if status = 0 then Msg('Build finished: no errors') else Msg('Build finished with exit status ' + IntToStr(status));
  end;
end;

procedure TApp.DoGrep;
var
  pat: string;
  status: Integer;
begin
  if not Prompt('Search files for: <Esc = abort>', WordUnderCursor, pat) then Exit;
  if pat = '' then Exit;
  RunToLog('grep -rnI --exclude-dir=.git -e ' + QuoteSh(pat) + ' . | sort -t: -k1,1 -k2,2n', grepDoc, '* Grep Log *', status);
  errLine := -1;
  DoNextError(1);
  if msgText = 'No more errors' then Msg('No matches for ' + pat);
end;

{ Look a name up in the nearest "tags" file (ctags format) and go to its definition. }
procedure TApp.DoTag;
var
  tag, dir, tagsFile, line, f, addr, pat, full: string;
  sl: TStringList;
  i, p, q, matches: Integer;
  fields: TStringList;
  found: Boolean;
  ln: Int64;
  cur_: string;
begin
  if not Prompt('Tag: <Esc = abort>', WordUnderCursor, tag) then Exit;
  tag := Trim(tag);
  if tag = '' then Exit;
  dir := ExtractFilePath(ExpandFileName(CD.Name));
  if dir = '' then dir := IncludeTrailingPathDelimiter(GetCurrentDir);
  tagsFile := '';
  repeat
    if FileExists(dir + 'tags') then begin tagsFile := dir + 'tags'; Break; end;
    cur_ := ExcludeTrailingPathDelimiter(dir);
    if (cur_ = '') or (ExtractFilePath(cur_) = dir) then Break;
    dir := ExtractFilePath(cur_);
  until False;
  if (tagsFile = '') and FileExists('tags') then tagsFile := ExpandFileName('tags');
  if tagsFile = '' then begin Msg('No tags file found (make one with ctags -R)'); Exit; end;
  sl := TStringList.Create;
  fields := TStringList.Create;
  try
    try
      sl.LoadFromFile(tagsFile);
    except
      Msg('Cannot read ' + tagsFile);
      Exit;
    end;
    matches := 0;
    f := ''; addr := '';
    for i := 0 to sl.Count - 1 do begin
      line := sl[i];
      if (line = '') or (line[1] = '!') then Continue;
      p := Pos(#9, line);
      if (p < 2) or (Copy(line, 1, p - 1) <> tag) then Continue;
      Inc(matches);
      if matches > 1 then Continue;
      fields.Clear;
      fields.Delimiter := #9;
      fields.StrictDelimiter := True;
      fields.DelimitedText := line;
      if fields.Count < 3 then Continue;
      f := fields[1];
      addr := fields[2];
      q := Pos(';"', addr);
      if q > 0 then addr := Copy(addr, 1, q - 1);
    end;
  finally
    sl.Free;
    fields.Free;
  end;
  if matches = 0 then begin Msg('Tag not found: ' + tag); Exit; end;
  full := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFilePath(tagsFile)) + f);
  if not FileExists(full) then begin Msg('Cannot find ' + full); Exit; end;
  OpenFile(full);
  SavePrev;
  ln := -1;
  if StrToInt64Def(addr, -1) > 0 then ln := StrToInt64(addr) - 1
  else if (addr <> '') and (addr[1] in ['/', '?']) then begin
    pat := Copy(addr, 2, Length(addr) - 2);
    if (pat <> '') and (pat[1] = '^') then Delete(pat, 1, 1);
    if (pat <> '') and (pat[Length(pat)] = '$') then SetLength(pat, Length(pat) - 1);
    pat := StringReplace(StringReplace(pat, '\/', '/', [rfReplaceAll]), '\\', '\', [rfReplaceAll]);
    found := False;
    i := 0;
    while CD.Seek(i) = i do begin
      if Pos(pat, CD.Get(i)) > 0 then begin ln := i; found := True; Break; end;
      Inc(i);
    end;
    if not found then begin GoLine(0); Msg('Tag found in ' + f + ' but not its text'); Exit; end;
  end;
  if ln >= 0 then GoLine(ln);
  CW.col := 0;
  if matches > 1 then Msg(IntToStr(matches) + ' matches for ' + tag + '; showing the first')
  else Msg(tag + ' in ' + ExtractFileName(f));
end;

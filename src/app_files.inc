{ ===================================================================== files }

function ExpandHome(const p: string): string;
begin
  Result := p;
  if (Length(p) >= 1) and (p[1] = '~') and ((Length(p) = 1) or (p[2] = '/')) then
    Result := GetEnvironmentVariable('HOME') + Copy(p, 2, MaxInt);
end;

procedure TApp.OpenFile(const path: string);
var
  full: string;
  d: TDoc;
  idx: Integer;
  sel: string;
begin
  full := ExpandFileName(ExpandHome(path));
  if DirectoryExists(full) then begin
    if not PickFile(IncludeTrailingPathDelimiter(full) + '*', sel) then Exit;
    OpenFile(sel);
    Exit;
  end;
  d := FindDoc(full);
  if d <> nil then begin
    ShowDoc(CW, d);
    Exit;
  end;
  try
    d := NewDoc(full);
  except
    on E: Exception do begin
      Msg('Cannot open ' + path + ': ' + E.Message);
      Exit;
    end;
  end;
  if (CW.doc <> nil) and (DocIndex(CW.doc) >= 0) then idx := DocIndex(CW.doc) + 1 else idx := docs.Count;
  docs.Insert(idx, d);
  ShowDoc(CW, d);
  if d.NewFile then Msg('New file');
end;

{ spec: one or more names separated by blanks; names with wildcards bring up a pick list }
procedure TApp.OpenFiles(const spec: string);
var
  parts: TStringList;
  i: Integer;
  sel: string;
begin
  parts := TStringList.Create;
  try
    parts.Delimiter := ' ';
    parts.StrictDelimiter := True;
    parts.DelimitedText := Trim(spec);
    for i := 0 to parts.Count - 1 do begin
      if parts[i] = '' then Continue;
      if (Pos('*', parts[i]) > 0) or (Pos('?', parts[i]) > 0) then begin
        if PickFile(ExpandHome(parts[i]), sel) then OpenFile(sel);
      end else
        OpenFile(parts[i]);
    end;
  finally
    parts.Free;
  end;
end;

function TApp.SaveDoc(d: TDoc): Boolean;
var
  err, fn: string;
begin
  Result := False;
  if d.Name = '' then begin
    if not Prompt('Save as: <Esc = abort>', '', fn) then Exit;
    fn := Trim(fn);
    if fn = '' then Exit;
    d.Name := ExpandFileName(ExpandHome(fn));
  end;
  if not d.Save(d.Name, optBackup, optTabsOut, err) then begin
    Msg('SAVE FAILED: ' + err);
    Exit;
  end;
  Msg('Saved ' + d.Name);
  Result := True;
end;

procedure TApp.CloseDoc(d: TDoc);
var
  idx, i, repl: Integer;
  inf: TDocInfo;
begin
  if bDoc = d then ClearBlock;
  idx := DocIndex(d);
  if idx < 0 then Exit;
  if docs.Count = 1 then begin
    for i := 0 to nwins - 1 do DetachDoc(wins[i]);
    docs.Delete(0);
    inf := Info(d);
    d.Free;
    inf.Free;
    running := False;
    Exit;
  end;
  if idx > 0 then repl := idx - 1 else repl := 1;
  for i := 0 to nwins - 1 do
    if wins[i].doc = d then ShowDoc(wins[i], TDoc(docs[repl]));
  docs.Delete(idx);
  inf := Info(d);
  d.Free;
  inf.Free;
end;

procedure TApp.DoNextPrevFile(dir: Integer);
var
  idx: Integer;
begin
  if docs.Count < 2 then begin Msg('Only one file is loaded'); Exit; end;
  idx := (DocIndex(CD) + dir + docs.Count) mod docs.Count;
  ShowDoc(CW, TDoc(docs[idx]));
end;

procedure TApp.DoEditFile;
var
  s: string;
begin
  if not Prompt('File(s) to edit: <Esc = abort>', '', s) then Exit;
  OpenFiles(s);
end;

procedure TApp.DoChangeName;
var
  s: string;
begin
  if not Prompt('New file name: <Esc = abort>', CD.Name, s) then Exit;
  s := Trim(s);
  if s = '' then Exit;
  s := ExpandFileName(ExpandHome(s));
  if (s <> CD.Name) and FileExists(s) then
    if AskKey('That file exists and will be overwritten on save. Continue? (Y/N)', 'YN') <> 'Y' then Exit;
  CD.Name := s;
  CD.NewFile := not FileExists(s);
  CD.Modified := True;
end;

{ 0 = Exit (ask), 1 = File (save), 2 = PQuit (warn), 3 = Quit (discard) }
procedure TApp.DoExit(mode: Integer);
var
  d: TDoc;
  c: Char;
begin
  d := CD;
  case mode of
    0: if d.Modified then begin
      c := AskKey('Save changes to ' + ExtractFileName(d.Name) + '? (Y/N, Esc = cancel)', 'YN');
      if c = #27 then Exit;
      if (c = 'Y') and (not SaveDoc(d)) then Exit;
    end;
    1: if d.Modified then
      if not SaveDoc(d) then Exit;
    2: if d.Modified then
      if AskKey('File has changed. Abandon the changes? (Y/N)', 'YN') <> 'Y' then Exit;
  end;
  CloseDoc(d);
end;

{ 0 = GExit (ask for each), 1 = GFile (save all, exit), 2 = GPQuit (warn, exit), 3 = GSave (save all) }
procedure TApp.DoGlobal(mode: Integer);
var
  i, n: Integer;
  d: TDoc;
  c: Char;
  list: TList;
begin
  list := TList.Create;
  try
    for i := 0 to docs.Count - 1 do list.Add(docs[i]);
    n := 0;
    for i := 0 to list.Count - 1 do if TDoc(list[i]).Modified then Inc(n);
    case mode of
      0: begin
        for i := 0 to list.Count - 1 do begin
          d := TDoc(list[i]);
          if not d.Modified then Continue;
          ShowDoc(CW, d);
          c := AskKey('Save changes to ' + ExtractFileName(d.Name) + '? (Y/N, Esc = cancel)', 'YN');
          if c = #27 then Exit;
          if (c = 'Y') and (not SaveDoc(d)) then Exit;
        end;
        running := False;
      end;
      1: begin
        for i := 0 to list.Count - 1 do begin
          d := TDoc(list[i]);
          if d.Modified then if not SaveDoc(d) then begin ShowDoc(CW, d); Exit; end;
        end;
        running := False;
      end;
      2: begin
        if n > 0 then
          if AskKey(IntToStr(n) + ' file(s) changed. Quit anyway? (Y/N)', 'YN') <> 'Y' then Exit;
        running := False;
      end;
      3: begin
        for i := 0 to list.Count - 1 do begin
          d := TDoc(list[i]);
          if d.Modified then if not SaveDoc(d) then begin ShowDoc(CW, d); Exit; end;
        end;
        Msg('Saved ' + IntToStr(n) + ' file(s)');
      end;
    end;
  finally
    list.Free;
  end;
end;

procedure TApp.DoKillFile;
var
  d: TDoc;
begin
  d := CD;
  if AskKey('Delete ' + d.Name + ' from disk? (Y/N)', 'YN') <> 'Y' then Exit;
  if FileExists(d.Name) then
    if not DeleteFile(d.Name) then begin Msg('Cannot delete ' + d.Name); Exit; end;
  CloseDoc(d);
end;

procedure TApp.DoShell;
var
  sh: string;
begin
  KeysDone;
  DoneVideo;
  WriteLn('Type "exit" to return to mkedit.');
  sh := GetEnvironmentVariable('SHELL');
  if sh = '' then sh := '/bin/sh';
  fpSystem(sh);
  InitVideo;
  KeysInit;
  ClearScreen;
  UpdateScreen(True);
end;

procedure TApp.DoDos;
var
  cmd: string;
begin
  if not Prompt('Execute what: <Esc = Abort>', '', cmd) then Exit;
  if Trim(cmd) = '' then Exit;
  KeysDone;
  DoneVideo;
  fpSystem(cmd);
  Write(LineEnding + 'Press Enter to return to mkedit...');
  ReadLn;
  InitVideo;
  KeysInit;
  ClearScreen;
  UpdateScreen(True);
end;

procedure RunPrint(const fileName: string; var res: string);
var
  cmd: string;
  rc: Integer;
begin
  cmd := GetEnvironmentVariable('MKEDIT_PRINT');
  if cmd = '' then cmd := 'lp';
  rc := fpSystem(cmd + ' "' + fileName + '" >/dev/null 2>&1');
  if rc = 0 then res := 'Sent to printer' else res := 'Print command failed: ' + cmd;
  DeleteFile(fileName);
end;

procedure TApp.DoPrint(whole: Boolean);
var
  tmp, res: string;
  f: TFileStream;
  ln, l1, l2: Int64;
  c1, c2, count, i: Integer;
  sc: TScrap;
  src: TDoc;

  procedure Emit(const t: string);
  var
    o: string;
  begin
    if (printPage > 0) and (count > 0) and (count mod printPage = 0) then begin
      o := #12;
      f.WriteBuffer(o[1], 1);
    end;
    o := Blanks(printLeft) + t + #10;
    f.WriteBuffer(o[1], Length(o));
    Inc(count);
  end;

begin
  if (not whole) and (not BlockRange(l1, c1, l2, c2)) then begin Msg('No block marked'); Exit; end;
  tmp := GetTempFileName('', 'mkedit-print-');
  count := 0;
  try
    f := TFileStream.Create(tmp, fmCreate);
    try
      if whole then begin
        src := CD;
        ln := 0;
        while src.Seek(ln) = ln do begin
          Emit(src.Get(ln));
          Inc(ln);
        end;
        src.Seek(CW.line);
      end else begin
        sc := ExtractBlock(bDoc, bKind, l1, c1, l2, c2);
        try
          for i := 0 to sc.lines.Count - 1 do Emit(sc.lines[i]);
        finally
          sc.Free;
        end;
      end;
    finally
      f.Free;
    end;
  except
    on E: Exception do begin Msg('Print failed: ' + E.Message); Exit; end;
  end;
  RunPrint(tmp, res);
  Msg(res);
end;

procedure TApp.DoPrintEject;
var
  tmp, res: string;
  f: TFileStream;
  c: Char;
begin
  tmp := GetTempFileName('', 'mkedit-print-');
  f := TFileStream.Create(tmp, fmCreate);
  try
    c := #12;
    f.WriteBuffer(c, 1);
  finally
    f.Free;
  end;
  RunPrint(tmp, res);
  Msg(res);
end;

{ ===================================================================== windows }

procedure TApp.WinSplit;
var
  w, nw: TWin;
  i, nh: Integer;
  d: TDoc;
begin
  if nwins >= MAXWIN then begin Msg('At most ' + IntToStr(MAXWIN) + ' windows'); Exit; end;
  zoomed := False;
  Relayout;
  w := CW;
  if w.h < 6 then begin Msg('Window too small to split'); Exit; end;
  nh := w.h div 2;
  nw := TWin.Create;
  nw.h := w.h - nh;
  w.h := nh;
  for i := nwins downto cur + 2 do wins[i] := wins[i - 1];
  wins[cur + 1] := nw;
  Inc(nwins);
  if docs.Count > 1 then d := TDoc(docs[(DocIndex(w.doc) + 1) mod docs.Count]) else d := w.doc;
  if d = w.doc then begin
    AttachDoc(nw, d);
    nw.line := w.line; nw.col := w.col; nw.left := w.left;
    nw.top := w.line - (nw.h - 1) div 2;
    if nw.top < 0 then nw.top := 0;
  end else
    ShowDoc(nw, d);
  Inc(cur);
  Relayout;
end;

procedure TApp.WinClose;
var
  w: TWin;
  i, nb: Integer;
begin
  if nwins = 1 then begin Msg('There is only one window'); Exit; end;
  w := CW;
  if cur > 0 then nb := cur - 1 else nb := 1;
  Inc(wins[nb].h, w.h);
  DetachDoc(w);
  w.Free;
  for i := cur to nwins - 2 do wins[i] := wins[i + 1];
  Dec(nwins);
  wins[nwins] := nil;
  if cur > 0 then Dec(cur);
  zoomed := False;
  Relayout;
end;

procedure TApp.WinOne;
var
  keep: TWin;
  i: Integer;
begin
  keep := CW;
  for i := 0 to nwins - 1 do
    if wins[i] <> keep then begin
      DetachDoc(wins[i]);
      wins[i].Free;
    end;
  wins[0] := keep;
  for i := 1 to MAXWIN - 1 do wins[i] := nil;
  nwins := 1;
  cur := 0;
  zoomed := False;
  keep.h := ScrH;
  Relayout;
end;

procedure TApp.WinNext(dir: Integer);
begin
  if nwins < 2 then Exit;
  cur := (cur + dir + nwins) mod nwins;
end;

procedure TApp.WinResize(grow: Boolean);
var
  k: TKey;
  w, o: TWin;
  done: Boolean;
begin
  if nwins < 2 then begin Msg('There is only one window'); Exit; end;
  zoomed := False;
  done := False;
  repeat
    Msg('Up/Down changes the window size; any other key ends');
    Refresh;
    repeat k := GetKey; until k.code <> kcNone;
    w := CW;
    if (k.code = kcUp) or (k.code = kcDown) then begin
      if grow then begin
        if k.code = kcUp then begin
          if cur > 0 then begin o := wins[cur - 1]; if o.h > 3 then begin Dec(o.h); Inc(w.h); end; end;
        end else begin
          if cur < nwins - 1 then begin o := wins[cur + 1]; if o.h > 3 then begin Dec(o.h); Inc(w.h); end; end;
        end;
      end else begin
        if k.code = kcUp then begin
          if (cur < nwins - 1) and (w.h > 3) then begin Dec(w.h); Inc(wins[cur + 1].h); end;
        end else begin
          if (cur > 0) and (w.h > 3) then begin Dec(w.h); Inc(wins[cur - 1].h); end;
        end;
      end;
    end else
      done := True;
  until done;
  msgText := '';
end;

{ ===================================================================== macros }

procedure TApp.DoMacroRecord;
var
  m: TMacro;
  k: TKey;
  nm: string;
  i, n: Integer;
begin
  if recording then begin
    n := Length(recBuf) - cmdKeys;
    if n < 0 then n := 0;
    m := TMacro.Create;
    SetLength(m.keys, n);
    for i := 0 to n - 1 do m.keys[i] := recBuf[i];
    if recKey = '' then begin
      scrapMacro.Free;
      scrapMacro := m;
    end else begin
      i := macros.IndexOf(recKey);
      if i >= 0 then begin TMacro(macros.Objects[i]).Free; macros.Delete(i); end;
      macros.AddObject(recKey, m);
    end;
    recording := False;
    SetLength(recBuf, 0);
    Msg('Macro recorded (' + IntToStr(n) + ' keys)');
    Exit;
  end;
  Msg('Assign to what key: (Enter for "scrap", Escape to abort)');
  Refresh;
  repeat k := GetKey; until k.code <> kcNone;
  msgText := '';
  if k.code = kcEsc then Exit;
  if k.code = kcEnter then nm := ''
  else begin
    nm := KeyName(k);
    if (nm = '') or ((bindMap.IndexOf(nm) >= 0) and (macros.IndexOf(nm) < 0)) then begin
      Msg('That key already has a command');
      Exit;
    end;
  end;
  recKey := nm;
  recording := True;
  SetLength(recBuf, 0);
  Msg('Recording macro; press the record key again to stop');
end;

procedure TApp.DoMacroPlay(const nm: string);
var
  m: TMacro;
  i, n: Integer;
begin
  if nm = '' then m := scrapMacro
  else begin
    i := macros.IndexOf(nm);
    if i < 0 then Exit;
    m := TMacro(macros.Objects[i]);
  end;
  if m = nil then begin Msg('No macro in the scrap area'); Exit; end;
  n := Length(inject) - injPos;
  if n > 200000 then Exit;
  { keep what is still queued, then the macro's keys }
  if injPos > 0 then begin
    for i := injPos to High(inject) do inject[i - injPos] := inject[i];
    SetLength(inject, Length(inject) - injPos);
    injPos := 0;
  end;
  i := Length(inject);
  SetLength(inject, i + Length(m.keys));
  for n := 0 to High(m.keys) do inject[i + n] := m.keys[n];
end;

procedure TApp.DoMacroFile(write: Boolean);
var
  fn, line, tok: string;
  sl, parts: TStringList;
  i, j, p: Integer;
  m: TMacro;
  k: TKey;
begin
  if write then begin
    if macros.Count = 0 then begin Msg('No macros to save'); Exit; end;
    if not Prompt('Macro file to write: <Esc = abort>', '', fn) then Exit;
  end else
    if not Prompt('Macro file to read: <Esc = abort>', '', fn) then Exit;
  fn := Trim(fn);
  if fn = '' then Exit;
  sl := TStringList.Create;
  try
    if write then begin
      for i := 0 to macros.Count - 1 do begin
        m := TMacro(macros.Objects[i]);
        line := macros[i] + #9;
        for j := 0 to High(m.keys) do begin
          if j > 0 then line := line + ' ';
          line := line + KeyName(m.keys[j]);
        end;
        sl.Add(line);
      end;
      try
        sl.SaveToFile(fn);
        Msg('Macros written to ' + fn);
      except
        on E: Exception do Msg('Cannot write ' + fn);
      end;
    end else begin
      if not FileExists(fn) then begin Msg('File not found: ' + fn); Exit; end;
      sl.LoadFromFile(fn);
      parts := TStringList.Create;
      try
        for i := 0 to sl.Count - 1 do begin
          line := sl[i];
          p := Pos(#9, line);
          if p < 2 then Continue;
          tok := Copy(line, 1, p - 1);
          parts.Clear;
          parts.Delimiter := ' ';
          parts.StrictDelimiter := True;
          parts.DelimitedText := Copy(line, p + 1, MaxInt);
          m := TMacro.Create;
          for j := 0 to parts.Count - 1 do begin
            if parts[j] = '' then Continue;
            k := KeyFromName(parts[j]);
            if k.code = kcNone then Continue;
            SetLength(m.keys, Length(m.keys) + 1);
            m.keys[High(m.keys)] := k;
          end;
          j := macros.IndexOf(tok);
          if j >= 0 then begin TMacro(macros.Objects[j]).Free; macros.Delete(j); end;
          macros.AddObject(tok, m);
        end;
      finally
        parts.Free;
      end;
      Msg('Macros read from ' + fn);
    end;
  finally
    sl.Free;
  end;
end;

{ ===================================================================== prompts }

function TApp.Prompt(const title, initial: string; out res: string): Boolean;
var
  s: string;
  p, w, x, y, fw, cc, vstart: Integer;
  fresh: Boolean;
  k: TKey;
  n, i: Integer;
begin
  s := initial;
  p := Length(s) + 1;
  fresh := initial <> '';
  Result := False;
  res := '';
  repeat
    DrawAll;
    w := ScrW - 2;
    if w > 76 then w := 76;
    if w < 24 then w := ScrW;
    x := (ScrW - w) div 2;
    y := ScrH div 2 - 2;
    if y < 0 then y := 0;
    ScrBox(x, y, w, 4, cBoxFg, cBoxBg, False);
    ScrPutsN(x + 2, y + 1, title, w - 4, cBoxFg, cBoxBg);
    fw := w - 4;
    cc := Utf8Len(Copy(s, 1, p - 1));
    vstart := 0;
    if cc >= fw then vstart := cc - fw + 1;
    { show the part of the text that holds the cursor (by characters) }
    n := 1;
    if vstart > 0 then begin
      i := vstart;
      while (i > 0) and (n <= Length(s)) do begin Inc(n, CharLen(s, n)); Dec(i); end;
    end;
    ScrFill(x + 2, y + 2, fw, 32, 0, 7);
    ScrPutsN(x + 2, y + 2, Copy(s, n, MaxInt), fw, 0, 7);
    if fresh then ScrAttr(x + 2, y + 2, Min(Utf8Len(s), fw), 15, 0);
    ScrCursor(x + 2 + cc - vstart, y + 2, False);
    ScrFlush;
    k := GetKey;
    case k.code of
      kcNone: ;
      kcEnter: begin res := s; Exit(True); end;
      kcEsc: Exit(False);
      kcBack: begin
        if fresh then begin s := ''; p := 1; end
        else if p > 1 then begin
          n := CharPrev(s, p);
          Delete(s, n, p - n);
          p := n;
        end;
        fresh := False;
      end;
      kcDel: begin
        if fresh then begin s := ''; p := 1; end
        else if p <= Length(s) then Delete(s, p, CharLen(s, p));
        fresh := False;
      end;
      kcLeft: begin if p > 1 then p := CharPrev(s, p); fresh := False; end;
      kcRight: begin if p <= Length(s) then p := CharNext(s, p); fresh := False; end;
      kcHome: begin p := 1; fresh := False; end;
      kcEnd: begin p := Length(s) + 1; fresh := False; end;
      kcChar: begin
        if (mCtrl in k.mods) then begin
          if k.ch = 'y' then begin s := ''; p := 1; end;
          fresh := False;
        end else if not (mAlt in k.mods) then begin
          if fresh then begin s := ''; p := 1; end;
          fresh := False;
          Insert(k.ch, s, p);
          Inc(p, Length(k.ch));
        end;
      end;
    end;
  until False;
end;

function TApp.PromptInt(const title: string; def, lo, hi: Integer; out v: Integer): Boolean;
var
  s: string;
begin
  Result := False;
  if not Prompt(title, IntToStr(def), s) then Exit;
  v := StrToIntDef(Trim(s), lo - 1);
  if (v < lo) or (v > hi) then begin
    Msg('Please enter a number from ' + IntToStr(lo) + ' to ' + IntToStr(hi));
    Exit;
  end;
  Result := True;
end;

function TApp.AskKey(const text, valid: string): Char;
var
  k: TKey;
  c: Char;
begin
  repeat
    DrawAll;
    ScrFill(0, ScrH - 1, ScrW, 32, cMsgFg, cMsgBg);
    ScrPutsN(1, ScrH - 1, text, ScrW - 2, cMsgFg, cMsgBg);
    ScrCursor(Min(ScrW - 1, Utf8Len(text) + 2), ScrH - 1, False);
    ScrFlush;
    k := GetKey;
    if k.code = kcEsc then Exit(#27);
    if (k.code = kcChar) and ((k.mods - [mShift]) = []) and (Length(k.ch) = 1) then begin
      c := UpCase(k.ch[1]);
      if Pos(c, UpperCase(valid)) > 0 then Exit(c);
    end;
  until False;
end;

{ ===================================================================== file picker }

{ * and ? wildcards, case-insensitive }
function WildMatch(const mask, name: string): Boolean;
var
  mi, ni, star, mark: Integer;
begin
  mi := 1; ni := 1; star := 0; mark := 0;
  while ni <= Length(name) do begin
    if (mi <= Length(mask)) and ((mask[mi] = '?') or (UpCase(mask[mi]) = UpCase(name[ni]))) then begin
      Inc(mi); Inc(ni);
    end else if (mi <= Length(mask)) and (mask[mi] = '*') then begin
      star := mi; mark := ni; Inc(mi);
    end else if star > 0 then begin
      mi := star + 1; Inc(mark); ni := mark;
    end else
      Exit(False);
  end;
  while (mi <= Length(mask)) and (mask[mi] = '*') do Inc(mi);
  Result := mi > Length(mask);
end;

function TApp.PickFile(const spec: string; out res: string): Boolean;
var
  dir, mask: string;
  names: TStringList;
  sr: TSearchRec;
  sel, topIdx, bw, bh, x, y, rows, i: Integer;
  k: TKey;
  isDir: Boolean;
  nm: string;

  procedure Load;
  var
    dl, fl: TStringList;
    i: Integer;
  begin
    names.Clear;
    dl := TStringList.Create;
    fl := TStringList.Create;
    try
      if FindFirst(dir + '*', faAnyFile, sr) = 0 then begin
        repeat
          if sr.Name = '.' then Continue;
          if (sr.Attr and faDirectory) <> 0 then dl.Add(sr.Name)
          else if WildMatch(mask, sr.Name) then fl.Add(sr.Name);
        until FindNext(sr) <> 0;
        FindClose(sr);
      end;
      dl.Sort;
      fl.Sort;
      for i := 0 to dl.Count - 1 do names.Add('/' + dl[i]);
      for i := 0 to fl.Count - 1 do names.Add(fl[i]);
    finally
      dl.Free;
      fl.Free;
    end;
    sel := 0;
    if (names.Count > 1) and (names[0] = '/..') then sel := 1;
    topIdx := 0;
  end;

begin
  Result := False;
  res := '';
  dir := ExtractFilePath(spec);
  mask := ExtractFileName(spec);
  if dir = '' then dir := './';
  if mask = '' then mask := '*';
  names := TStringList.Create;
  try
    Load;
    if (names.Count = 0) or ((names.Count = 1) and (names[0] = '/..')) then begin
      Msg('No files match ' + spec);
      Exit;
    end;
    repeat
      DrawAll;
      bw := Min(ScrW - 4, 64);
      bh := Min(ScrH - 4, 22);
      if bh < 5 then bh := Min(ScrH, 5);
      x := (ScrW - bw) div 2;
      y := (ScrH - bh) div 2;
      rows := bh - 2;
      if sel < topIdx then topIdx := sel;
      if sel >= topIdx + rows then topIdx := sel - rows + 1;
      ScrBox(x, y, bw, bh, 0, 7, True);
      ScrPutsN(x + 2, y, ' ' + dir + mask + ' ', bw - 4, 0, 7);
      for i := 0 to rows - 1 do
        if topIdx + i < names.Count then begin
          nm := names[topIdx + i];
          if topIdx + i = sel then begin
            ScrFill(x + 1, y + 1 + i, bw - 2, 32, 15, 0);
            ScrPutsN(x + 2, y + 1 + i, nm, bw - 4, 15, 0);
          end else
            ScrPutsN(x + 2, y + 1 + i, nm, bw - 4, 0, 7);
        end;
      ScrHideCursor;
      ScrFlush;
      k := GetKey;
      case k.code of
        kcEsc: Exit(False);
        kcUp: if sel > 0 then Dec(sel);
        kcDown: if sel < names.Count - 1 then Inc(sel);
        kcPgUp: sel := Max(0, sel - rows);
        kcPgDn: sel := Min(names.Count - 1, sel + rows);
        kcHome: sel := 0;
        kcEnd: sel := names.Count - 1;
        kcEnter: begin
          nm := names[sel];
          isDir := (nm <> '') and (nm[1] = '/');
          if isDir then begin
            Delete(nm, 1, 1);
            dir := ExpandFileName(IncludeTrailingPathDelimiter(dir) + nm);
            dir := IncludeTrailingPathDelimiter(dir);
            Load;
          end else begin
            res := dir + nm;
            Exit(True);
          end;
        end;
        kcChar: begin
          { type-ahead: jump to the first name starting with the character }
          if (k.mods = []) and (Length(k.ch) = 1) then
            for i := 0 to names.Count - 1 do begin
              nm := names[i];
              if (nm <> '') and (nm[1] = '/') then Delete(nm, 1, 1);
              if (nm <> '') and (UpCase(nm[1]) = UpCase(k.ch[1])) then begin sel := i; Break; end;
            end;
        end;
      end;
    until False;
  finally
    names.Free;
  end;
end;

{ ===================================================================== help }

procedure TApp.ShowHelp;
var
  lines: TStringList;
  W2, H2, top, i, y, wl, rest, wm, wr, x2, x3, hy: Integer;
  k: TKey;
  t: string;

  procedure Section(const title: string; const rows: array of string; x, y, w: Integer);
  var
    r, p, lw: Integer;
    lbl, keys: string;
  begin
    ScrBox(x, y, w, Length(rows) + 2, 11, 1, False);
    ScrPutsN(x + 1, y, title, w - 2, 15, 1);
    lw := 17;
    for r := 0 to High(rows) do begin
      p := Pos('|', rows[r]);
      lbl := Copy(rows[r], 1, p - 1);
      keys := Copy(rows[r], p + 1, MaxInt);
      ScrPutsN(x + 1, y + 1 + r, lbl, lw, 7, 1);
      ScrPutsN(x + 1 + lw, y + 1 + r, keys, w - 2 - lw, 14, 1);
    end;
  end;

  procedure Add(const title: string; const rows: array of string);
  var
    r: Integer;
  begin
    lines.Add('=' + title);
    for r := 0 to High(rows) do lines.Add(rows[r]);
    lines.Add('');
  end;

begin
  W2 := ScrW;
  H2 := ScrH;
  if W2 >= 96 then begin
    repeat
      ScrClear(7, 1);
      ScrBox(0, 0, W2, Min(H2, 33), 15, 1, False);
      ScrPutsN(2, 0, ' mkedit Help ', 20, 15, 1);
      ScrPutsN(18, 0, ' Press <Esc> for the Menus, any other key to return ', W2 - 20, 14, 1);
      wl := 34;
      rest := W2 - wl - 4;
      wm := rest div 2;
      wr := rest - wm - 1;
      x2 := wl + 2;
      x3 := x2 + wm + 1;
      Section('Block', HelpBlock, 2, 1, wl);
      Section('Edit', HelpEdit, 2, 1 + Length(HelpBlock) + 2, wl);
      { cursor spans two columns }
      ScrBox(x2, 1, rest + 1, Length(HelpCursor1) + 2, 11, 1, False);
      ScrPutsN(x2 + 1, 1, 'Cursor', 10, 15, 1);
      for i := 0 to High(HelpCursor1) do begin
        t := HelpCursor1[i];
        ScrPutsN(x2 + 1, 2 + i, Copy(t, 1, Pos('|', t) - 1), 17, 7, 1);
        ScrPutsN(x2 + 18, 2 + i, Copy(t, Pos('|', t) + 1, MaxInt), 8, 14, 1);
        t := HelpCursor2[i];
        ScrPutsN(x3, 2 + i, Copy(t, 1, Pos('|', t) - 1), 17, 7, 1);
        ScrPutsN(x3 + 18, 2 + i, Copy(t, Pos('|', t) + 1, MaxInt), 8, 14, 1);
      end;
      hy := 1 + Length(HelpCursor1) + 2;
      Section('Files', HelpFiles, x2, hy, wm);
      Section('Macro', HelpMacro, x2, hy + Length(HelpFiles) + 2, wm);
      Section('Windows', HelpWindows, x3, hy, wr + 1);
      Section('Search/Replace', HelpSearch, x3, hy + Length(HelpWindows) + 2, wr + 1);
      ScrHideCursor;
      ScrFlush;
      k := GetKey;
      if k.code <> kcNone then Break;
    until False;
  end else begin
    lines := TStringList.Create;
    try
      Add('Block', HelpBlock);
      Add('Cursor', HelpCursor1);
      Add('', HelpCursor2);
      Add('Edit', HelpEdit);
      Add('Files', HelpFiles);
      Add('Windows', HelpWindows);
      Add('Search/Replace', HelpSearch);
      Add('Macro', HelpMacro);
      top := 0;
      repeat
        ScrClear(7, 1);
        ScrFill(0, 0, W2, 32, 0, 7);
        ScrPutsN(1, 0, 'mkedit Help: Up/Down scroll, Esc = menus, other key = back', W2 - 2, 0, 7);
        y := 1;
        i := top;
        while (y < H2) and (i < lines.Count) do begin
          t := lines[i];
          if (t <> '') and (t[1] = '=') then ScrPutsN(1, y, Copy(t, 2, MaxInt), W2 - 2, 15, 1)
          else if t <> '' then begin
            ScrPutsN(2, y, Copy(t, 1, Pos('|', t) - 1), 18, 7, 1);
            ScrPutsN(20, y, Copy(t, Pos('|', t) + 1, MaxInt), W2 - 22, 14, 1);
          end;
          Inc(y); Inc(i);
        end;
        ScrHideCursor;
        ScrFlush;
        k := GetKey;
        case k.code of
          kcUp: if top > 0 then Dec(top);
          kcDown: if top < lines.Count - 1 then Inc(top);
          kcPgUp: top := Max(0, top - (H2 - 2));
          kcPgDn: top := Min(lines.Count - 1, top + (H2 - 2));
          kcNone: ;
        else
          Break;
        end;
      until False;
    finally
      lines.Free;
    end;
  end;
  if k.code = kcEsc then RunMenu(-1);
end;

{ ===================================================================== menus }

function KeyHint(bindMap: TStringList; cmd: TCmd): string;
var
  i, p: Integer;
  k, best: string;
begin
  best := '';
  for i := 0 to bindMap.Count - 1 do
    if TCmd(PtrInt(bindMap.Objects[i])) = cmd then begin
      k := bindMap[i];
      if k = 'ESC' then Continue;
      p := Pos(' ', k);
      if p > 0 then k := KeyLabel(Copy(k, 1, p - 1)) + UpperCase(Copy(k, p + 1, MaxInt))
      else k := KeyLabel(k);
      if (best = '') or (Length(k) < Length(best)) then best := k;
    end;
  Result := best;
end;

{ start: index of the pull-down to open, or -1 to begin with the bar only }
procedure TApp.RunMenu(start: Integer);
var
  sel, item, i, x, y, w, mw, wmax, kw: Integer;
  open: Boolean;
  k: TKey;
  chosen: TCmd;
  c: Char;
  t, hint: string;
  mx: array of Integer;
  hints: array of string;

  procedure Layout;
  var
    j, xx: Integer;
  begin
    SetLength(mx, Length(Menus));
    xx := 1;
    for j := 0 to High(Menus) do begin
      mx[j] := xx;
      Inc(xx, Length(Menus[j].title) + 2);
    end;
  end;

begin
  chosen := cmNone;
  Layout;
  if start >= 0 then begin sel := start; open := True; end else begin sel := 0; open := False; end;
  item := 0;
  repeat
    DrawAll;
    { the bar }
    ScrFill(0, 0, ScrW, 32, cMenuFg, cMenuBg);
    for i := 0 to High(Menus) do begin
      t := ' ' + Menus[i].title + ' ';
      if i = sel then ScrPutsN(mx[i] - 1, 0, t, ScrW, cMenuSelFg, cMenuSelBg)
      else begin
        ScrPutsN(mx[i] - 1, 0, t, ScrW, cMenuFg, cMenuBg);
        ScrAttr(mx[i], 0, 1, cHotFg, cMenuBg);
      end;
    end;
    if open then begin
      wmax := 0;
      kw := 0;
      SetLength(hints, Length(Menus[sel].items));
      for i := 0 to High(Menus[sel].items) do begin
        wmax := Max(wmax, Length(Menus[sel].items[i].text));
        hints[i] := KeyHint(bindMap, Menus[sel].items[i].cmd);
        kw := Max(kw, Length(hints[i]));
      end;
      w := wmax + kw + 5;
      if kw = 0 then w := wmax + 4;
      x := mx[sel] - 1;
      if x + w > ScrW then x := Max(0, ScrW - w);
      y := 1;
      ScrBox(x, y, w, Length(Menus[sel].items) + 2, cMenuFg, cMenuBg, False);
      for i := 0 to High(Menus[sel].items) do begin
        if i = item then begin
          ScrFill(x + 1, y + 1 + i, w - 2, 32, cMenuSelFg, cMenuSelBg);
          ScrPutsN(x + 2, y + 1 + i, Menus[sel].items[i].text, w - 4, cMenuSelFg, cMenuSelBg);
          ScrPutsN(x + w - 2 - Length(hints[i]), y + 1 + i, hints[i], w - 4, cMenuSelFg, cMenuSelBg);
        end else begin
          ScrPutsN(x + 2, y + 1 + i, Menus[sel].items[i].text, w - 4, cMenuFg, cMenuBg);
          ScrPutsN(x + w - 2 - Length(hints[i]), y + 1 + i, hints[i], w - 4, 1, cMenuBg);
        end;
      end;
    end;
    ScrHideCursor;
    ScrFlush;
    k := GetKey;
    case k.code of
      kcNone: ;
      kcEsc: begin if open and (start < 0) then open := False else Break; end;
      kcLeft: begin sel := (sel + High(Menus)) mod Length(Menus); item := 0; end;
      kcRight: begin sel := (sel + 1) mod Length(Menus); item := 0; end;
      kcDown: begin
        if not open then begin open := True; item := 0; end
        else item := (item + 1) mod Length(Menus[sel].items);
      end;
      kcUp: begin
        if open then item := (item + Length(Menus[sel].items) - 1) mod Length(Menus[sel].items);
      end;
      kcHome: item := 0;
      kcEnd: if open then item := High(Menus[sel].items);
      kcEnter: begin
        if not open then begin open := True; item := 0; end
        else begin chosen := Menus[sel].items[item].cmd; Break; end;
      end;
      kcChar: begin
        if (k.mods = []) and (Length(k.ch) = 1) then begin
          c := UpCase(k.ch[1]);
          if open then begin
            for i := 0 to High(Menus[sel].items) do
              if UpCase(Menus[sel].items[i].hot) = c then begin
                chosen := Menus[sel].items[i].cmd;
                Break;
              end;
            if chosen <> cmNone then Break;
          end else
            for i := 0 to High(Menus) do
              if Menus[i].hot = c then begin sel := i; open := True; item := 0; Break; end;
        end;
      end;
    end;
  until False;
  if chosen <> cmNone then Execute(chosen);
end;

{ ===================================================================== command dispatch }

procedure TApp.Execute(cmd: TCmd);
var
  v: Integer;
  s: string;
begin
  lastCmd := cmd;
  case cmd of
    { --- cursor --- }
    cmCursorUp: if optBox then DoBoxMove(1) else MoveUp;
    cmCursorDown: if optBox then DoBoxMove(3) else MoveDown;
    cmCursorLeft: if optBox then DoBoxMove(4) else begin if CW.col > 0 then Dec(CW.col); end;
    cmCursorRight: if optBox then DoBoxMove(2) else begin if CW.col < MAXCOL then Inc(CW.col); end;
    cmBegLine: CW.col := 0;
    cmEndLine: CW.col := EndCol(CurText);
    cmBegFile: DoBegEndFile(False);
    cmEndFile: DoBegEndFile(True);
    cmBegScreen: begin CW.line := CW.top; GoLine(CW.line); end;
    cmEndScreen: begin GoLine(CW.top + CW.h - 2); end;
    cmGotoBlockBeg: DoGotoBlock(False);
    cmGotoBlockEnd: DoGotoBlock(True);
    cmGotoLine: DoGotoLine;
    cmPageDown: MovePage(1, False);
    cmPageUp: MovePage(-1, False);
    cmHalfPgDn: MovePage(1, True);
    cmHalfPgUp: MovePage(-1, True);
    cmLineUp: ScrollView(-1, True);
    cmLineDown: ScrollView(1, True);
    cmScrollUp: ScrollView(-1, False);
    cmScrollDown: ScrollView(1, False);
    cmMakeTopofScreen: PlaceScreen(0);
    cmMakeCtrofScreen: PlaceScreen(1);
    cmMakeBotofScreen: PlaceScreen(2);
    cmScreenLeft: begin Dec(CW.left, scrStep); if CW.left < 0 then CW.left := 0; if CW.col >= CW.left + ScrW then CW.col := CW.left + ScrW - 1; end;
    cmScreenRight: begin Inc(CW.left, scrStep); if CW.col < CW.left then CW.col := CW.left; end;
    cmWordLeft: DoWordLeft;
    cmWordRight: DoWordRight;
    cmPrevPosition: begin
      if CW.prevValid then begin
        v := CW.col;
        s := '';
        GoLine(CW.prevLine);
        CW.col := CW.prevCol;
        SavePrev;
        CW.prevCol := v;
      end else Msg('No previous position');
    end;
    { --- editing --- }
    cmAddLine: begin CD.InsertLine(CW.line + 1, ''); Inc(CW.line); end;
    cmInsertLine: begin CD.InsertLine(CW.line, ''); Dec(CW.line); end;
    cmAlign: DoAlign;
    cmBackspace: DoBackspace;
    cmDelCh: DoDelCh;
    cmDelLine: begin
      KillText(kkLine, CurText);
      CD.DeleteLine(CW.line);
      GoLine(CW.line);
    end;
    cmDelLtWord: DoDelLtWord;
    cmDelRtWord: DoDelRtWord;
    cmDelToEol: begin
      s := CurText;
      v := 0;
      KillText(kkFrag, Copy(s, CurIdx(s, v), MaxInt));
      if v = 0 then SetCurText(Copy(s, 1, CurIdx(s, v) - 1));
    end;
    cmDupLine: begin CD.InsertLine(CW.line + 1, CurText); Inc(CW.line); end;
    cmGetPrev: DoGetPrev;
    cmJoinLine: DoJoinLine;
    cmLiteral: DoLiteral;
    cmReturn: DoReturn;
    cmSplitLine: DoSplitLine;
    cmUnKill: DoUnKill;
    cmUndoCursorline: DoUndoLine;
    cmTabRt: DoTab(True);
    cmTabLt: DoTab(False);
    cmWrapPara: DoWrapPara;
    cmCurrentFilename: TypeText(CD.Name);
    cmInsertDate: TypeText(FormatDateTime('yyyy-mm-dd hh:nn', Now));
    cmInsertTime: TypeText(FormatDateTime('hh:nn:ss', Now));
    cmMatch: DoMatch;
    { --- blocks --- }
    cmDropAnchor: MarkToggle(bkStream, True);
    cmMarkCharacter: MarkToggle(bkStream, False);
    cmMarkLine: MarkToggle(bkLine, False);
    cmMarkColumn: MarkToggle(bkColumn, True);
    cmMarkBlockBegin: MarkBegin;
    cmMarkBlockEnd: MarkEnd;
    cmUnmarkBlock: ClearBlock;
    cmCopyBlock: DoCopyMove(False, False);
    cmCopyOverBlock: DoCopyMove(False, True);
    cmMoveBlock: DoCopyMove(True, False);
    cmDeleteBlock: DoDeleteBlock;
    cmCopy: DoCutCopy(False);
    cmCut: DoCutCopy(True);
    cmPaste: DoPaste(False);
    cmPasteOver: DoPaste(True);
    cmShiftLeft: DoShift(False);
    cmShiftRight: DoShift(True);
    cmStoreScrbuff: DoScratch(0);
    cmAppendScrbuff: DoScratch(1);
    cmGetScrbuff: DoScratch(2);
    cmReadBlock: DoReadBlock;
    cmWriteBlock: DoWriteBlock;
    { --- files --- }
    cmEditFile: DoEditFile;
    cmChangeFilename: DoChangeName;
    cmNextFile: DoNextPrevFile(1);
    cmPrevFile: DoNextPrevFile(-1);
    cmSaveFile: SaveDoc(CD);
    cmExit: DoExit(0);
    cmFile: DoExit(1);
    cmPQuit: DoExit(2);
    cmQuit: DoExit(3);
    cmGExit: DoGlobal(0);
    cmGFile: DoGlobal(1);
    cmGPQuit: DoGlobal(2);
    cmGSave: DoGlobal(3);
    cmKillFile: DoKillFile;
    cmShell: DoShell;
    cmDos: DoDos;
    cmPrintAll: DoPrint(True);
    cmPrintBlock: DoPrint(False);
    cmPrintEject: DoPrintEject;
    cmSetPrintLeftMargin: if PromptInt('Printer left margin [0..80]: <Esc = Abort>', printLeft, 0, 80, v) then printLeft := v;
    cmSetPrintPageSize: if PromptInt('Printer page size [0..400]: <Esc = Abort>', printPage, 0, 400, v) then printPage := v;
    { --- windows --- }
    cmHorizontalWindow: WinSplit;
    cmCloseWindow: WinClose;
    cmOneWindow: WinOne;
    cmNextWindow: WinNext(1);
    cmPrevWindow: WinNext(-1);
    cmGrowWindow: WinResize(True);
    cmShrinkWindow: WinResize(False);
    cmZoomWindow: begin if nwins > 1 then zoomed := not zoomed else Msg('There is only one window'); end;
    { --- macros --- }
    cmMacroRecord: DoMacroRecord;
    cmExecuteScrap: DoMacroPlay('');
    cmMacroRead: DoMacroFile(False);
    cmMacroWrite: DoMacroFile(True);
    { --- search --- }
    cmFind: DoFind(False);
    cmFindReplace: DoFind(True);
    cmRepeatFind: DoRepeatFind;
    { --- options --- }
    cmToggleInsert: begin optInsert := not optInsert; end;
    cmToggleIndent: begin optIndent := not optIndent; if optIndent then Msg('AutoIndent ON') else Msg('AutoIndent OFF'); end;
    cmToggleWordwrap: begin optWrap := not optWrap; if optWrap then Msg('WordWrap ON') else Msg('WordWrap OFF'); end;
    cmToggleBoxDraw: begin optBox := not optBox; if optBox then Msg('Box drawing ON') else Msg('Box drawing OFF'); end;
    cmToggleEnterMatching: begin optMatching := not optMatching; if optMatching then Msg('EnterMatching ON') else Msg('EnterMatching OFF'); end;
    cmToggleSmartTabs: begin optSmart := not optSmart; if optSmart then Msg('Smart tabs ON') else Msg('Smart tabs OFF'); end;
    cmToggleTabsExpand: begin
      Info(CD).expand := not Info(CD).expand;
      if Info(CD).expand then Msg('Tab key inserts blanks') else Msg('Tab key inserts a physical tab');
    end;
    cmToggleTabsOut: begin optTabsOut := not optTabsOut; if optTabsOut then Msg('Tabs out ON: blanks become tabs on save') else Msg('Tabs out OFF'); end;
    cmToggleBakups: begin optBackup := not optBackup; if optBackup then Msg('Backup files ON (.bak)') else Msg('Backup files OFF'); end;
    cmSetRmargin: if PromptInt('right margin [1..300]: <Esc = abort>', rmargin, 1, 300, v) then begin rmargin := v; optWrap := True; end;
    cmSetPtabwidth: if PromptInt('Physical tab width [1..16]: <Esc = abort>', ptab, 1, 16, v) then ptab := v;
    cmSetCtabwidth: if PromptInt('C tab width [1..16]: <Esc = abort>', ctab, 1, 16, v) then ctab := v;
    { --- other --- }
    cmQuickHelp: ShowHelp;
    cmMainMenu: RunMenu(-1);
    cmMenuFile: RunMenu(0);
    cmMenuPrint: RunMenu(7);
    cmMenuQuit: RunMenu(8);
  end;
end;

procedure TApp.DoGotoBlock(atEnd: Boolean);
var
  l1, l2: Int64;
  c1, c2: Integer;
begin
  if not BlockRange(l1, c1, l2, c2) then begin Msg('No block marked'); Exit; end;
  if bDoc <> CD then ShowDoc(CW, bDoc);
  SavePrev;
  if atEnd then begin
    GoLine(l2);
    if bKind = bkLine then CW.col := 0 else CW.col := c2;
  end else begin
    GoLine(l1);
    if bKind = bkLine then CW.col := 0 else CW.col := c1;
  end;
end;

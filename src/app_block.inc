{ ===================================================================== blocks }

procedure TApp.SetBlockDoc(d: TDoc);
begin
  if bDoc = d then Exit;
  if bDoc <> nil then begin
    bDoc.RemoveAnchor(@bSL);
    bDoc.RemoveAnchor(@bEL);
  end;
  bDoc := d;
  if d <> nil then begin
    d.AddAnchor(@bSL);
    d.AddAnchor(@bEL);
  end;
end;

procedure TApp.ClearBlock;
begin
  SetBlockDoc(nil);
  bKind := bkNone;
  bFollow := False;
  bHalf := 0;
end;

function TApp.BlockActive: Boolean;
var
  l1, l2: Int64;
  c1, c2: Integer;
begin
  Result := BlockRange(l1, c1, l2, c2);
end;

{ DropAnchor / MarkLine / MarkColumn: the first press starts a block that follows the cursor, the
  second press fixes its end. Pressing again while a block exists extends it. }
procedure TApp.MarkToggle(kind: TBlockKind; incl: Boolean);
begin
  if bHalf <> 0 then ClearBlock;
  if (bKind <> bkNone) and (bDoc = CD) and bFollow and (bKind = kind) then begin
    bEL := CW.line;
    bEC := CW.col;
    bFollow := False;
    Msg('Block marked');
    Exit;
  end;
  if (bKind <> bkNone) and (bDoc = CD) and (not bFollow) then begin
    { extend the existing block to the cursor }
    if (CW.line < bSL) or ((CW.line = bSL) and (CW.col < bSC)) then begin
      bSL := CW.line; bSC := CW.col;
    end else begin
      bEL := CW.line; bEC := CW.col;
    end;
    bKind := kind;
    bIncl := incl;
    Exit;
  end;
  ClearBlock;
  SetBlockDoc(CD);
  bKind := kind;
  bIncl := incl;
  bSL := CW.line; bSC := CW.col;
  bEL := CW.line; bEC := CW.col;
  bFollow := True;
end;

{ ^KB and ^KK: the block is not shown until both ends have been marked. }
procedure TApp.MarkBegin;
begin
  if (bKind <> bkNone) and (bDoc <> CD) then ClearBlock;
  if bKind = bkNone then begin
    SetBlockDoc(CD);
    bKind := bkStream;
    bIncl := False;
    bFollow := False;
    bSL := CW.line; bSC := CW.col;
    bEL := CW.line; bEC := CW.col;
    bHalf := 1;
    Msg('Block begin marked; mark its end with F8');
  end else begin
    bSL := CW.line; bSC := CW.col;
    if bHalf = 2 then bHalf := 0;
    if bHalf = 0 then begin bKind := bkStream; bIncl := False; bFollow := False; end;
  end;
end;

procedure TApp.MarkEnd;
begin
  if (bKind <> bkNone) and (bDoc <> CD) then ClearBlock;
  if bKind = bkNone then begin
    SetBlockDoc(CD);
    bKind := bkStream;
    bIncl := False;
    bFollow := False;
    bSL := CW.line; bSC := CW.col;
    bEL := CW.line; bEC := CW.col;
    bHalf := 2;
    Msg('Block end marked; mark its begin with F7');
  end else begin
    bEL := CW.line; bEC := CW.col;
    bFollow := False;
    if bHalf = 1 then bHalf := 0;
    if bHalf = 0 then begin bKind := bkStream; bIncl := False; end;
  end;
end;

function TApp.ExtractBlock(d: TDoc; kind: TBlockKind; l1: Int64; c1: Integer; l2: Int64; c2: Integer): TScrap;
var
  sc: TScrap;
  ln: Int64;
  s: string;
  i1, i2, pad: Integer;
begin
  sc := TScrap.Create;
  sc.kind := kind;
  case kind of
    bkLine: begin
      for ln := l1 to l2 do begin
        d.Seek(ln);
        sc.lines.Add(d.Get(ln));
      end;
    end;
    bkColumn: begin
      for ln := l1 to l2 do begin
        d.Seek(ln);
        sc.lines.Add(ColSlice(d.Get(ln), c1, c2, TabStop));
      end;
    end;
  else
    d.Seek(l1);
    s := d.Get(l1);
    i1 := IdxOfCol(s, c1, TabStop, pad);
    if l1 = l2 then begin
      i2 := IdxOfCol(s, c2, TabStop, pad);
      sc.lines.Add(Copy(s, i1, i2 - i1));
    end else begin
      sc.lines.Add(Copy(s, i1, MaxInt));
      for ln := l1 + 1 to l2 - 1 do begin
        d.Seek(ln);
        sc.lines.Add(d.Get(ln));
      end;
      d.Seek(l2);
      s := d.Get(l2);
      i2 := IdxOfCol(s, c2, TabStop, pad);
      sc.lines.Add(Copy(s, 1, i2 - 1));
    end;
  end;
  Result := sc;
end;

procedure TApp.RemoveBlock(d: TDoc; kind: TBlockKind; l1: Int64; c1: Integer; l2: Int64; c2: Integer);
var
  ln: Int64;
  s, s1, s2: string;
  i1, i2, pad, k: Integer;
begin
  case kind of
    bkLine: begin
      for ln := l1 to l2 do begin
        d.Seek(l1);
        d.DeleteLine(l1);
      end;
    end;
    bkColumn: begin
      for ln := l1 to l2 do begin
        d.Seek(ln);
        s := d.Get(ln);
        i1 := IdxOfCol(s, c1, TabStop, pad);
        if i1 <= Length(s) then begin
          i2 := IdxOfCol(s, c2, TabStop, pad);
          d.SetLine(ln, Copy(s, 1, i1 - 1) + Copy(s, i2, MaxInt));
        end;
      end;
    end;
  else
    d.Seek(l1);
    s1 := d.Get(l1);
    i1 := IdxOfCol(s1, c1, TabStop, pad);
    if l1 = l2 then begin
      i2 := IdxOfCol(s1, c2, TabStop, pad);
      d.SetLine(l1, Copy(s1, 1, i1 - 1) + Copy(s1, i2, MaxInt));
    end else begin
      d.Seek(l2);
      s2 := d.Get(l2);
      i2 := IdxOfCol(s2, c2, TabStop, pad);
      s2 := Copy(s2, i2, MaxInt);
      for k := 1 to l2 - l1 do begin
        d.Seek(l1 + 1);
        d.DeleteLine(l1 + 1);
      end;
      d.Seek(l1);
      d.SetLine(l1, Copy(s1, 1, i1 - 1) + s2);
    end;
  end;
  d.Seek(l1);
end;

{ Insert a block of text. For stream and column blocks at (line, col); for line blocks before or
  after line as configured. eL/eC: where the inserted text ends (exclusive column). }
procedure TApp.InsertScrap(d: TDoc; sc: TScrap; line: Int64; col: Integer; over: Boolean;
                           out eL: Int64; out eC: Integer);
var
  s, before, after, t: string;
  idx, pad, i, n, w, ia, ib: Integer;
  at, ln: Int64;
begin
  eL := line; eC := col;
  n := sc.lines.Count;
  if n = 0 then Exit;
  d.Seek(line);
  case sc.kind of
    bkLine: begin
      if optLineBefore then at := line else at := line + 1;
      for i := 0 to n - 1 do begin
        d.Seek(at + i);
        d.InsertLine(at + i, sc.lines[i]);
      end;
      eL := at + n - 1;
      eC := 0;
    end;
    bkColumn: begin
      w := 0;
      for i := 0 to n - 1 do w := Max(w, LineWidth(sc.lines[i], TabStop));
      for i := 0 to n - 1 do begin
        ln := line + i;
        if d.Seek(ln) <> ln then begin
          d.InsertLine(d.LastLine + 1, '');
          d.Seek(ln);
        end;
        s := d.Get(ln);
        t := PadTo(sc.lines[i], w, TabStop);
        if over then begin
          s := PadTo(s, col, TabStop);
          ia := IdxOfCol(s, col, TabStop, pad);
          ib := IdxOfCol(s, col + w, TabStop, pad);
          s := Copy(s, 1, ia - 1) + t + Copy(s, ib, MaxInt);
        end else begin
          idx := IdxOfCol(s, col, TabStop, pad);
          if pad > 0 then begin s := s + Blanks(pad); idx := Length(s) + 1; end;
          s := Copy(s, 1, idx - 1) + t + Copy(s, idx, MaxInt);
        end;
        d.SetLine(ln, s);
      end;
      eL := line + n - 1;
      eC := col + w;
    end;
  else
    s := d.Get(line);
    idx := IdxOfCol(s, col, TabStop, pad);
    if pad > 0 then begin s := s + Blanks(pad); idx := Length(s) + 1; end;
    before := Copy(s, 1, idx - 1);
    after := Copy(s, idx, MaxInt);
    if n = 1 then begin
      d.SetLine(line, before + sc.lines[0] + after);
      eL := line;
      eC := col + LineWidth(sc.lines[0], TabStop);
    end else begin
      d.SetLine(line, before + sc.lines[0]);
      for i := 1 to n - 2 do begin
        d.Seek(line + i);
        d.InsertLine(line + i, sc.lines[i]);
      end;
      d.Seek(line + n - 1);
      d.InsertLine(line + n - 1, sc.lines[n - 1] + after);
      eL := line + n - 1;
      eC := LineWidth(sc.lines[n - 1], TabStop);
    end;
  end;
end;

procedure TApp.DoCopyMove(move, over: Boolean);
var
  l1, l2, eL, at: Int64;
  c1, c2, eC: Integer;
  kind: TBlockKind;
  sc: TScrap;
  inside: Boolean;
  src: TDoc;
  n: Integer;
begin
  if not BlockRange(l1, c1, l2, c2) then begin Msg('No block marked'); Exit; end;
  src := bDoc;
  kind := bKind;
  if over and (kind <> bkColumn) then begin Msg('CopyOverBlock is for column blocks'); Exit; end;
  if move and (src = CD) then begin
    inside := False;
    case kind of
      bkLine: inside := (CW.line >= l1) and (CW.line <= l2);
      bkColumn: inside := (CW.line >= l1) and (CW.line <= l2) and (CW.col >= c1) and (CW.col < c2);
    else
      inside := ((CW.line > l1) or ((CW.line = l1) and (CW.col >= c1))) and
                ((CW.line < l2) or ((CW.line = l2) and (CW.col < c2)));
    end;
    if inside then begin Msg('The cursor is inside the block'); Exit; end;
  end;
  sc := ExtractBlock(src, kind, l1, c1, l2, c2);
  try
    if move then begin
      { the cursor's column moves when text before it on its line is removed }
      if src = CD then begin
        if (kind = bkStream) and (CW.line = l2) and (CW.col >= c2) then begin
          if l1 = l2 then Dec(CW.col, c2 - c1) else CW.col := c1 + (CW.col - c2);
        end else if (kind = bkColumn) and (CW.line >= l1) and (CW.line <= l2) and (CW.col >= c2) then
          Dec(CW.col, c2 - c1);
      end;
      RemoveBlock(src, kind, l1, c1, l2, c2);
      if src = CD then GoLine(CW.line);
    end;
    n := sc.lines.Count;
    if kind = bkLine then begin
      if optLineBefore then at := CW.line else at := CW.line + 1;
    end else
      at := CW.line;
    InsertScrap(CD, sc, CW.line, CW.col, over, eL, eC);
    { the new text becomes the marked block }
    ClearBlock;
    SetBlockDoc(CD);
    bKind := kind;
    bFollow := False;
    case kind of
      bkLine: begin bSL := eL - n + 1; bEL := eL; bSC := 0; bEC := 0; end;
      bkColumn: begin bSL := at; bSC := CW.col; bEL := eL; bEC := eC - 1; end;
    else
      bSL := at; bSC := CW.col; bEL := eL; bEC := eC; bIncl := False;
    end;
    if kind = bkLine then begin CW.line := bSL; end;
    GoLine(CW.line);
  finally
    sc.Free;
  end;
  if move then Msg('Block moved') else Msg('Block copied');
end;

procedure TApp.DoDeleteBlock;
var
  l1, l2: Int64;
  c1, c2: Integer;
  sc: TScrap;
begin
  if not BlockRange(l1, c1, l2, c2) then begin Msg('No block marked'); Exit; end;
  if bDoc <> CD then begin Msg('The block is in another file'); Exit; end;
  if bKind = bkColumn then begin Msg('Use Cut to delete a column block'); Exit; end;
  sc := ExtractBlock(CD, bKind, l1, c1, l2, c2);
  KillPush(kkBlock, sc);
  RemoveBlock(CD, bKind, l1, c1, l2, c2);
  CW.line := l1;
  if bKind = bkLine then CW.col := 0 else CW.col := c1;
  ClearBlock;
  GoLine(CW.line);
end;

{ The block, or the cursor line if none is marked and that is allowed. }
function TApp.BlockOrLine(out sc: TScrap; out l1: Int64; out c1: Integer; out l2: Int64; out c2: Integer;
                          out kind: TBlockKind): Boolean;
begin
  Result := False;
  sc := nil;
  if BlockRange(l1, c1, l2, c2) then begin
    kind := bKind;
    sc := ExtractBlock(bDoc, kind, l1, c1, l2, c2);
    Exit(True);
  end;
  if optCutLine then begin
    kind := bkLine;
    l1 := CW.line; l2 := CW.line; c1 := 0; c2 := MaxInt;
    sc := ExtractBlock(CD, kind, l1, c1, l2, c2);
    Exit(True);
  end;
  Msg('No block marked');
end;

procedure TApp.DoCutCopy(cut: Boolean);
var
  sc: TScrap;
  l1, l2: Int64;
  c1, c2: Integer;
  kind: TBlockKind;
  src: TDoc;
  fromBlock: Boolean;
begin
  fromBlock := BlockActive;
  if not BlockOrLine(sc, l1, c1, l2, c2, kind) then Exit;
  if fromBlock then src := bDoc else src := CD;
  scrap.CopyFrom(sc);
  sc.Free;
  if cut then begin
    if src <> CD then begin Msg('The block is in another file'); Exit; end;
    if (kind = bkStream) and (CW.line = l2) and (CW.col >= c2) then begin
      if l1 = l2 then Dec(CW.col, c2 - c1) else CW.col := c1 + (CW.col - c2);
    end;
    RemoveBlock(CD, kind, l1, c1, l2, c2);
    if (CW.line >= l1) and (CW.line <= l2) then begin
      CW.line := l1;
      if kind = bkLine then CW.col := 0 else CW.col := c1;
    end;
    ClearBlock;
    GoLine(CW.line);
    Msg('Cut to scrap buffer');
  end else
    begin
      if fromBlock then ClearBlock;
      Msg('Copied to scrap buffer');
    end;
end;

{ Insert a scrap at the cursor. Line scraps leave the cursor on their first line, stream scraps put it
  just after the text, so that pasting again continues where the last paste ended. }
procedure TApp.PasteScrap(sc: TScrap; over: Boolean);
var
  eL: Int64;
  eC: Integer;
  at: Int64;
begin
  if sc.lines.Count = 0 then begin Msg('Nothing to paste'); Exit; end;
  if sc.kind = bkLine then begin
    if optLineBefore then at := CW.line else at := CW.line + 1;
  end else at := CW.line;
  InsertScrap(CD, sc, CW.line, CW.col, over and (sc.kind = bkColumn), eL, eC);
  case sc.kind of
    bkLine: CW.line := at;
    bkStream: begin CW.line := eL; CW.col := eC; end;
  end;
  GoLine(CW.line);
end;

procedure TApp.DoPaste(over: Boolean);
begin
  if scrap.lines.Count = 0 then begin Msg('The scrap buffer is empty'); Exit; end;
  PasteScrap(scrap, over);
end;

procedure TApp.DoShift(right: Boolean);
var
  l1, l2, ln: Int64;
  c1, c2: Integer;
  s: string;
begin
  if BlockRange(l1, c1, l2, c2) and (bDoc = CD) and (CW.line >= l1) and (CW.line <= l2) then begin
  end else begin
    l1 := CW.line; l2 := CW.line;
  end;
  for ln := l1 to l2 do begin
    CD.Seek(ln);
    s := CD.Get(ln);
    if right then begin
      if s <> '' then CD.SetLine(ln, ' ' + s);
    end else begin
      if (s <> '') and (s[1] = ' ') then CD.SetLine(ln, Copy(s, 2, MaxInt))
      else if (s <> '') and (s[1] = #9) then CD.SetLine(ln, Blanks(TabStop - 1) + Copy(s, 2, MaxInt));
    end;
  end;
  GoLine(CW.line);
end;

{ 0 = store, 1 = append, 2 = get }
procedure TApp.DoScratch(mode: Integer);
var
  nm, ttl: string;
  sc, ex: TScrap;
  i, j: Integer;
  l1, l2: Int64;
  c1, c2: Integer;
  kind: TBlockKind;
begin
  case mode of
    0: ttl := 'Store to buffer: <Esc = abort>';
    1: ttl := 'Append to buffer: <Esc = abort>';
  else ttl := 'Get from buffer: <Esc = abort>';
  end;
  if not Prompt(ttl, '', nm) then Exit;
  nm := Trim(nm);
  if nm = '' then Exit;
  i := scratch.IndexOf(nm);
  if mode = 2 then begin
    if i < 0 then begin Msg('No such scratch buffer'); Exit; end;
    PasteScrap(TScrap(scratch.Objects[i]), False);
    Exit;
  end;
  if not BlockActive then begin Msg('No block marked'); Exit; end;
  if not BlockRange(l1, c1, l2, c2) then Exit;
  kind := bKind;
  ex := ExtractBlock(bDoc, kind, l1, c1, l2, c2);
  if (mode = 1) and (i >= 0) then begin
    sc := TScrap(scratch.Objects[i]);
    if (sc.kind = bkStream) and (ex.kind = bkStream) and (sc.lines.Count > 0) then begin
      sc.lines[sc.lines.Count - 1] := sc.lines[sc.lines.Count - 1] + ex.lines[0];
      for j := 1 to ex.lines.Count - 1 do sc.lines.Add(ex.lines[j]);
    end else begin
      for j := 0 to ex.lines.Count - 1 do sc.lines.Add(ex.lines[j]);
      if sc.kind <> ex.kind then sc.kind := bkLine;
    end;
    ex.Free;
  end else begin
    if i >= 0 then begin TScrap(scratch.Objects[i]).Free; scratch.Delete(i); end;
    scratch.AddObject(nm, ex);
  end;
  Msg('Block saved in scratch buffer ' + nm);
end;

procedure TApp.DoReadBlock;
var
  fn, content: string;
  sc: TScrap;
  f: TFileStream;
  p, q: Integer;
  eL, at: Int64;
  eC: Integer;
begin
  if not Prompt('File to read: <Esc = abort>', '', fn) then Exit;
  fn := Trim(fn);
  if fn = '' then Exit;
  if not FileExists(fn) then begin Msg('File not found: ' + fn); Exit; end;
  try
    f := TFileStream.Create(fn, fmOpenRead or fmShareDenyNone);
    try
      SetLength(content, f.Size);
      if f.Size > 0 then f.ReadBuffer(content[1], f.Size);
    finally
      f.Free;
    end;
  except
    on E: Exception do begin Msg('Cannot read ' + fn); Exit; end;
  end;
  sc := TScrap.Create;
  try
    sc.kind := bkStream;
    p := 1;
    while p <= Length(content) + 1 do begin
      q := p;
      while (q <= Length(content)) and (content[q] <> #10) do Inc(q);
      if (q > p) and (content[q - 1] = #13) then sc.lines.Add(ExpandTabs(Copy(content, p, q - p - 1), TabStop))
      else sc.lines.Add(ExpandTabs(Copy(content, p, q - p), TabStop));
      p := q + 1;
    end;
    at := CW.line;
    InsertScrap(CD, sc, CW.line, CW.col, False, eL, eC);
    ClearBlock;
    SetBlockDoc(CD);
    bKind := bkStream; bFollow := False; bIncl := False;
    bSL := at; bSC := CW.col; bEL := eL; bEC := eC;
    GoLine(CW.line);
  finally
    sc.Free;
  end;
  Msg('Read ' + fn);
end;

procedure TApp.DoWriteBlock;
var
  fn: string;
  sc: TScrap;
  l1, l2: Int64;
  c1, c2: Integer;
  f: TFileStream;
  i: Integer;
  eol, s: string;
begin
  if not BlockRange(l1, c1, l2, c2) then begin Msg('No block marked'); Exit; end;
  if not Prompt('File to write: <Esc = abort>', '', fn) then Exit;
  fn := Trim(fn);
  if fn = '' then Exit;
  if FileExists(fn) then
    if UpCase(AskKey('File exists. Overwrite? (Y/N)', 'YN')) <> 'Y' then Exit;
  sc := ExtractBlock(bDoc, bKind, l1, c1, l2, c2);
  try
    if bDoc.Eol = eolCRLF then eol := #13#10 else eol := #10;
    try
      f := TFileStream.Create(fn, fmCreate);
      try
        for i := 0 to sc.lines.Count - 1 do begin
          s := sc.lines[i];
          if (i < sc.lines.Count - 1) or (sc.kind <> bkStream) then s := s + eol;
          if s <> '' then f.WriteBuffer(s[1], Length(s));
        end;
      finally
        f.Free;
      end;
      Msg('Wrote ' + IntToStr(sc.lines.Count) + ' lines to ' + fn);
    except
      on E: Exception do Msg('Cannot write ' + fn);
    end;
  finally
    sc.Free;
  end;
end;

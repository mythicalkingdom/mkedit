program doctest;
{$mode objfpc}{$H+}
{ Model-based stress test of the sliding buffer: random seeks/edits/saves against a plain TStringList. }
uses SysUtils, Classes, Math, uDoc;

var
  fails: Integer = 0;

procedure Check(c: Boolean; const msg: string);
begin
  if not c then begin
    Inc(fails);
    WriteLn('FAIL: ', msg);
    if fails > 10 then Halt(1);
  end;
end;

function RandLine(i: Integer): string;
var
  n, k: Integer;
begin
  n := Random(5);
  case n of
    0: Result := '';
    1: Result := 'line ' + IntToStr(i);
    2: begin Result := ''; for k := 1 to Random(200) do Result := Result + Chr(33 + Random(90)); end;
  else
    Result := 'Line number ' + IntToStr(i) + ' with some filler text to make it longer';
  end;
end;

procedure WriteModel(const fn: string; m: TStringList; crlf, finalNL: Boolean);
var
  f: TFileStream;
  i: Integer;
  s, e: string;
begin
  if crlf then e := #13#10 else e := #10;
  f := TFileStream.Create(fn, fmCreate);
  try
    for i := 0 to m.Count - 1 do begin
      s := m[i];
      if (i < m.Count - 1) or finalNL then s := s + e;
      if Length(s) > 0 then f.WriteBuffer(s[1], Length(s));
    end;
  finally
    f.Free;
  end;
end;

function FileAsLines(const fn: string; crlf: Boolean; out finalNL: Boolean): TStringList;
var
  f: TFileStream;
  s: string;
  i, j: Integer;
begin
  Result := TStringList.Create;
  f := TFileStream.Create(fn, fmOpenRead);
  try
    SetLength(s, f.Size);
    if f.Size > 0 then f.ReadBuffer(s[1], f.Size);
  finally
    f.Free;
  end;
  finalNL := (Length(s) > 0) and (s[Length(s)] = #10);
  i := 1;
  while i <= Length(s) do begin
    j := i;
    while (j <= Length(s)) and (s[j] <> #10) do Inc(j);
    if crlf and (j > i) and (s[j - 1] = #13) then Result.Add(Copy(s, i, j - i - 1))
    else Result.Add(Copy(s, i, j - i));
    i := j + 1;
  end;
end;

procedure RunCase(const label_: string; nLines, nOps: Integer; crlf, finalNL: Boolean);
var
  fn: string;
  model, got: TStringList;
  d: TDoc;
  i, op, ln, a: Integer;
  cur: Int64;
  fnl: Boolean;
  s: string;
  round: Integer;
begin
  fn := GetEnvironmentVariable('DOCTEST_FILE');
  model := TStringList.Create;
  for i := 0 to nLines - 1 do model.Add(RandLine(i));
  if model.Count = 0 then model.Add('');
  WriteModel(fn, model, crlf, finalNL);
  d := TDoc.Create(fn, False, 8);
  cur := 0;
  for round := 1 to 3 do begin
    for op := 1 to nOps do begin
      case Random(10) of
        0: cur := Random(model.Count);                 { far jump }
        1: cur := cur + Random(2000) - 1000;
        2: cur := 0;
        3: cur := model.Count - 1;
      else
        cur := cur + Random(40) - 20;
      end;
      if cur < 0 then cur := 0;
      if cur >= model.Count then cur := model.Count - 1;
      a := d.Seek(cur);
      Check(a = cur, label_ + ': Seek returned ' + IntToStr(a) + ' want ' + IntToStr(cur));
      Check(d.InBuf(cur), label_ + ': line not in buffer');
      Check(d.Get(cur) = model[cur], label_ + ': content mismatch at ' + IntToStr(cur));
      case Random(6) of
        0: begin s := RandLine(op); d.SetLine(cur, s); model[cur] := s; end;
        1: begin s := RandLine(op); d.InsertLine(cur, s); model.Insert(cur, s); end;
        2: if model.Count > 1 then begin d.DeleteLine(cur); model.Delete(cur); end;
        3: begin s := RandLine(op); d.InsertLine(cur + 1, s); model.Insert(cur + 1, s); end;
      end;
      if cur >= model.Count then cur := model.Count - 1;
    end;
    { spot-check many lines }
    for i := 1 to 200 do begin
      ln := Random(model.Count);
      a := d.Seek(ln);
      Check(d.Get(ln) = model[ln], label_ + ': spot mismatch at ' + IntToStr(ln));
    end;
    { go to the end: line count must agree }
    a := d.Seek(High(Int32));
    Check(d.LastLineKnown, label_ + ': last line should be known');
    Check(d.LastLine = model.Count - 1, label_ + ': line count ' + IntToStr(d.LastLine + 1) + ' want ' + IntToStr(model.Count));
    { save and compare }
    Check(d.Save(fn, False, False, s), label_ + ': save failed: ' + s);
    got := FileAsLines(fn, crlf, fnl);
    Check(got.Count = model.Count, label_ + ': saved line count ' + IntToStr(got.Count) + ' want ' + IntToStr(model.Count));
    for i := 0 to Min(got.Count, model.Count) - 1 do
      if got[i] <> model[i] then begin Check(False, label_ + ': saved line differs at ' + IntToStr(i)); Break; end;
    got.Free;
    Check(not d.Modified, label_ + ': still modified after save');
  end;
  d.Free;
  model.Free;
  DeleteFile(fn);
end;

begin
  Randomize;
  RandSeed := 12345;
  RunCase('big LF', 40000, 3000, False, True);
  RunCase('big CRLF', 20000, 2000, True, True);
  RunCase('no final newline', 5000, 1500, False, False);
  RunCase('small', 30, 300, False, True);
  RunCase('tiny', 1, 100, False, True);
  RunCase('mid', 1500, 1500, False, True);
  if fails = 0 then WriteLn('doctest: all passed') else begin WriteLn('doctest: ', fails, ' failures'); Halt(1); end;
end.

unit uScreen;
{$mode objfpc}{$H+}
{$POINTERMATH ON}
{ A thin wrapper over the Video unit's cell buffer. Cells hold CP437 bytes; strings passed to
  ScrPuts are UTF-8 and are mapped to CP437 (characters with no CP437 equivalent show as '?'). }

interface

uses Video, uCP437;

function ScrW: Integer;
function ScrH: Integer;
procedure ScrClear(fg, bg: Byte);
procedure ScrPut(x, y: Integer; ch: Byte; fg, bg: Byte);
function ScrPutsN(x, y: Integer; const s: string; maxCols: Integer; fg, bg: Byte): Integer;
function ScrPuts(x, y: Integer; const s: string; fg, bg: Byte): Integer;
procedure ScrFill(x, y, w: Integer; ch: Byte; fg, bg: Byte);
procedure ScrFlush;
procedure ScrCursor(x, y: Integer; block: Boolean);
procedure ScrHideCursor;
{ Rectangle with single or double line border, filled inside with blanks }
procedure ScrBox(x, y, w, h: Integer; fg, bg: Byte; dbl: Boolean);
{ Draw a CP437 byte / change only the colours of a run of cells }
procedure ScrAttr(x, y, w: Integer; fg, bg: Byte);
function ScrCharAt(x, y: Integer): Byte;

implementation

function ScrW: Integer;
begin
  Result := ScreenWidth;
end;

function ScrH: Integer;
begin
  Result := ScreenHeight;
end;

function Attr(fg, bg: Byte): Word;
begin
  Result := Word(((bg and 7) shl 4) or (fg and 15)) shl 8;
end;

procedure ScrClear(fg, bg: Byte);
var
  i: Integer;
  w: Word;
  p: PWord;
begin
  w := Attr(fg, bg) or 32;
  p := PWord(VideoBuf);
  for i := 0 to ScreenWidth * ScreenHeight - 1 do p[i] := w;
end;

procedure ScrPut(x, y: Integer; ch: Byte; fg, bg: Byte);
begin
  if (x < 0) or (y < 0) or (x >= ScreenWidth) or (y >= ScreenHeight) then Exit;
  PWord(VideoBuf)[y * ScreenWidth + x] := Attr(fg, bg) or ch;
end;

{ Write at most maxCols characters; returns the next x. }
function ScrPutsN(x, y: Integer; const s: string; maxCols: Integer; fg, bg: Byte): Integer;
var
  i, k, cols, m: Integer;
  cp: Cardinal;
  b: Byte;
begin
  i := 1;
  cols := 0;
  while (i <= Length(s)) and (cols < maxCols) do begin
    k := Utf8Decode(@s[i], Length(s) - i + 1, cp);
    if k = 0 then begin
      b := Byte(s[i]);
      k := 1;
    end else if cp < 128 then
      b := Byte(cp)
    else begin
      m := UniToCp437(cp);
      if m < 0 then b := 63 else b := m;
    end;
    ScrPut(x + cols, y, b, fg, bg);
    Inc(cols);
    Inc(i, k);
  end;
  Result := x + cols;
end;

function ScrPuts(x, y: Integer; const s: string; fg, bg: Byte): Integer;
begin
  Result := ScrPutsN(x, y, s, MaxInt, fg, bg);
end;

procedure ScrFill(x, y, w: Integer; ch: Byte; fg, bg: Byte);
var
  i: Integer;
begin
  for i := 0 to w - 1 do ScrPut(x + i, y, ch, fg, bg);
end;

procedure ScrFlush;
begin
  UpdateScreen(False);
end;

procedure ScrCursor(x, y: Integer; block: Boolean);
begin
  if (x < 0) or (y < 0) or (x >= ScreenWidth) or (y >= ScreenHeight) then begin
    SetCursorType(crHidden);
    Exit;
  end;
  SetCursorPos(x, y);
  if block then SetCursorType(crBlock) else SetCursorType(crUnderline);
end;

procedure ScrHideCursor;
begin
  SetCursorType(crHidden);
end;

procedure ScrBox(x, y, w, h: Integer; fg, bg: Byte; dbl: Boolean);
var
  i, j: Integer;
  tl, tr, bl, br, hz, vt: Byte;
begin
  if dbl then begin tl := 201; tr := 187; bl := 200; br := 188; hz := 205; vt := 186; end
  else begin tl := 218; tr := 191; bl := 192; br := 217; hz := 196; vt := 179; end;
  for j := 0 to h - 1 do
    for i := 0 to w - 1 do begin
      if (j = 0) and (i = 0) then ScrPut(x, y, tl, fg, bg)
      else if (j = 0) and (i = w - 1) then ScrPut(x + i, y, tr, fg, bg)
      else if (j = h - 1) and (i = 0) then ScrPut(x, y + j, bl, fg, bg)
      else if (j = h - 1) and (i = w - 1) then ScrPut(x + i, y + j, br, fg, bg)
      else if (j = 0) or (j = h - 1) then ScrPut(x + i, y + j, hz, fg, bg)
      else if (i = 0) or (i = w - 1) then ScrPut(x + i, y + j, vt, fg, bg)
      else ScrPut(x + i, y + j, 32, fg, bg);
    end;
end;

procedure ScrAttr(x, y, w: Integer; fg, bg: Byte);
var
  i: Integer;
  p: PWord;
begin
  if (y < 0) or (y >= ScreenHeight) then Exit;
  p := PWord(VideoBuf);
  for i := x to x + w - 1 do
    if (i >= 0) and (i < ScreenWidth) then
      p[y * ScreenWidth + i] := Attr(fg, bg) or (p[y * ScreenWidth + i] and $FF);
end;

function ScrCharAt(x, y: Integer): Byte;
begin
  if (x < 0) or (y < 0) or (x >= ScreenWidth) or (y >= ScreenHeight) then Exit(32);
  Result := PWord(VideoBuf)[y * ScreenWidth + x] and $FF;
end;

end.

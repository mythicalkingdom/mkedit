unit uText;
{$mode objfpc}{$H+}
{ Line-level helpers. A line is a byte string. Valid UTF-8 sequences count as one character (one
  screen column); any other byte is one character too. A tab advances to the next tab stop.
  "Column" always means a 0-based screen column; "index" is a 1-based byte index into the string. }

interface

const
  MAXCOL = 1000;       { how far the cursor may wander past the end of a line }

function CharLen(const s: string; i: Integer): Integer;
function CharNext(const s: string; i: Integer): Integer;
function CharPrev(const s: string; i: Integer): Integer;
function ColOfIdx(const s: string; idx, tabw: Integer): Integer;
{ idx of the character that covers column col; Length(s)+1 (and pad = columns past the end) if beyond }
function IdxOfCol(const s: string; col, tabw: Integer; out pad: Integer): Integer;
function LineWidth(const s: string; tabw: Integer): Integer;
function ExpandTabs(const s: string; tabw: Integer): string;
function CompressTabs(const s: string; tabw: Integer): string;
function IsWordCh(c: Char): Boolean;
function IsBlankCh(c: Char): Boolean;
{ 1-based index of the first non-blank, 0 if none }
function FirstNonBlank(const s: string): Integer;
{ 1-based index of the last non-blank, 0 if none }
function LastNonBlank(const s: string): Integer;
function RTrim(const s: string): string;
function LTrim(const s: string): string;
{ Display column of the first non-blank (0 if the line is blank) }
function IndentCol(const s: string; tabw: Integer): Integer;
function Blanks(n: Integer): string;
{ Pad s with blanks to display width w (never shortens) }
function PadTo(const s: string; w, tabw: Integer): string;
{ Text of columns [c1, c2) of s, padded with blanks to exactly c2-c1 columns }
function ColSlice(const s: string; c1, c2, tabw: Integer): string;

implementation

uses Math, uCP437;

function CharLen(const s: string; i: Integer): Integer;
var
  cp: Cardinal;
  k: Integer;
begin
  if (i < 1) or (i > Length(s)) then Exit(1);
  if Byte(s[i]) < $80 then Exit(1);
  k := Utf8Decode(@s[i], Length(s) - i + 1, cp);
  if k = 0 then k := 1;
  Result := k;
end;

function CharNext(const s: string; i: Integer): Integer;
begin
  Result := i + CharLen(s, i);
end;

function CharPrev(const s: string; i: Integer): Integer;
var
  j: Integer;
begin
  { i is the index just after a character; return the start of that character }
  if i <= 1 then Exit(1);
  j := i - 1;
  if j > Length(s) then Exit(j);
  if Byte(s[j]) >= $80 then begin
    { back over continuation bytes, at most three }
    while (j > 1) and (i - j < 4) and ((Byte(s[j]) and $C0) = $80) do Dec(j);
    if CharNext(s, j) <> i then j := i - 1;
  end;
  Result := j;
end;

function ColOfIdx(const s: string; idx, tabw: Integer): Integer;
var
  i, c: Integer;
begin
  c := 0;
  i := 1;
  while (i < idx) and (i <= Length(s)) do begin
    if s[i] = #9 then c := c + tabw - (c mod tabw) else Inc(c);
    i := CharNext(s, i);
  end;
  if idx > Length(s) + 1 then c := c + (idx - Length(s) - 1);
  Result := c;
end;

function IdxOfCol(const s: string; col, tabw: Integer; out pad: Integer): Integer;
var
  i, c, w: Integer;
begin
  i := 1;
  c := 0;
  pad := 0;
  while i <= Length(s) do begin
    if s[i] = #9 then w := tabw - (c mod tabw) else w := 1;
    if col < c + w then Exit(i);
    c := c + w;
    i := CharNext(s, i);
  end;
  pad := col - c;
  if pad < 0 then pad := 0;
  Result := Length(s) + 1;
end;

function LineWidth(const s: string; tabw: Integer): Integer;
begin
  Result := ColOfIdx(s, Length(s) + 1, tabw);
end;

function ExpandTabs(const s: string; tabw: Integer): string;
var
  i, c, n: Integer;
begin
  if Pos(#9, s) = 0 then Exit(s);
  Result := '';
  c := 0;
  i := 1;
  while i <= Length(s) do begin
    if s[i] = #9 then begin
      n := tabw - (c mod tabw);
      Result := Result + StringOfChar(' ', n);
      Inc(c, n);
      Inc(i);
    end else begin
      n := CharLen(s, i);
      Result := Result + Copy(s, i, n);
      Inc(c);
      Inc(i, n);
    end;
  end;
end;

{ Replace runs of blanks that end on a tab stop by tabs. Text inside single or double quotes is left
  alone. }
function CompressTabs(const s: string; tabw: Integer): string;
var
  i, c, n, runStart, runCols, nxt: Integer;
  q: Char;
  out_: string;
begin
  if Pos('  ', s) = 0 then Exit(s);
  out_ := '';
  q := #0;
  c := 0;
  i := 1;
  while i <= Length(s) do begin
    if q <> #0 then begin
      if s[i] = q then q := #0;
      out_ := out_ + s[i]; Inc(c); Inc(i);
      Continue;
    end;
    if (s[i] = '"') or (s[i] = '''') then begin
      q := s[i]; out_ := out_ + s[i]; Inc(c); Inc(i);
      Continue;
    end;
    if s[i] = ' ' then begin
      runStart := c;
      runCols := 0;
      nxt := i;
      while (nxt <= Length(s)) and (s[nxt] = ' ') do begin Inc(nxt); Inc(runCols); end;
      { emit tabs for every tab stop crossed inside the run, then the leftover blanks }
      n := runStart;
      while (n div tabw + 1) * tabw <= runStart + runCols do begin
        if (n div tabw + 1) * tabw - n >= 2 then out_ := out_ + #9
        else out_ := out_ + StringOfChar(' ', (n div tabw + 1) * tabw - n);
        n := (n div tabw + 1) * tabw;
      end;
      out_ := out_ + StringOfChar(' ', runStart + runCols - n);
      c := runStart + runCols;
      i := nxt;
      Continue;
    end;
    n := CharLen(s, i);
    out_ := out_ + Copy(s, i, n);
    Inc(c);
    Inc(i, n);
  end;
  Result := out_;
end;

function IsWordCh(c: Char): Boolean;
begin
  Result := (c in ['0'..'9', 'A'..'Z', 'a'..'z', '_']) or (Byte(c) >= $80);
end;

function IsBlankCh(c: Char): Boolean;
begin
  Result := (c = ' ') or (c = #9);
end;

function FirstNonBlank(const s: string): Integer;
var
  i: Integer;
begin
  for i := 1 to Length(s) do
    if not IsBlankCh(s[i]) then Exit(i);
  Result := 0;
end;

function LastNonBlank(const s: string): Integer;
var
  i: Integer;
begin
  for i := Length(s) downto 1 do
    if not IsBlankCh(s[i]) then Exit(i);
  Result := 0;
end;

function RTrim(const s: string): string;
begin
  Result := Copy(s, 1, LastNonBlank(s));
end;

function LTrim(const s: string): string;
var
  i: Integer;
begin
  i := FirstNonBlank(s);
  if i = 0 then Result := '' else Result := Copy(s, i, MaxInt);
end;

function IndentCol(const s: string; tabw: Integer): Integer;
var
  i: Integer;
begin
  i := FirstNonBlank(s);
  if i = 0 then Result := 0 else Result := ColOfIdx(s, i, tabw);
end;

function Blanks(n: Integer): string;
begin
  if n <= 0 then Result := '' else Result := StringOfChar(' ', n);
end;

function PadTo(const s: string; w, tabw: Integer): string;
var
  cw: Integer;
begin
  cw := LineWidth(s, tabw);
  if cw >= w then Result := s else Result := s + StringOfChar(' ', w - cw);
end;

function ColSlice(const s: string; c1, c2, tabw: Integer): string;
var
  i, c, w, n: Integer;
begin
  Result := '';
  if c2 <= c1 then Exit;
  c := 0;
  i := 1;
  while (i <= Length(s)) and (c < c2) do begin
    if s[i] = #9 then w := tabw - (c mod tabw) else w := 1;
    n := CharLen(s, i);
    if (c >= c1) and (c + w <= c2) then
      Result := Result + Copy(s, i, n)
    else begin
      { a tab (or nothing) straddling a slice edge: use blanks for the visible part }
      if (c + w > c1) and (c < c2) then
        Result := Result + StringOfChar(' ', Min(c + w, c2) - Max(c, c1));
    end;
    c := c + w;
    Inc(i, n);
  end;
  w := c2 - c1 - ColOfIdx(Result, Length(Result) + 1, tabw);
  if w > 0 then Result := Result + StringOfChar(' ', w);
end;

end.

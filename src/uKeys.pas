unit uKeys;
{$mode objfpc}{$H+}
{ Keyboard input for a Unix terminal: raw mode, xterm/VT/Linux-console escape sequences including
  Shift/Alt/Ctrl modifiers, UTF-8 typed text, bracketed paste, and a short timeout so a lone Esc is
  delivered as Esc. Keys are normalised to names such as 'C-K', 'A-x', 'F5', 'S-F5', 'C-PGUP' which
  the key binding table and the macro files use. }

interface

type
  TKeyCode = (kcNone, kcChar, kcUp, kcDown, kcLeft, kcRight, kcPgUp, kcPgDn, kcHome, kcEnd,
              kcIns, kcDel, kcEnter, kcEsc, kcBack, kcTab, kcF, kcPasteBegin, kcPasteEnd);
  TMod = (mShift, mCtrl, mAlt);
  TMods = set of TMod;
  TKey = record
    code: TKeyCode;
    mods: TMods;
    ch: string;      { kcChar: the UTF-8 character; with mCtrl: the lower-case letter or symbol }
    n: Integer;      { kcF: the function key number }
  end;

var
  Hangup: Boolean = False;      { the terminal went away, or SIGHUP/SIGTERM arrived }

procedure KeysInit;
procedure KeysDone;
{ Non-blocking: True with the next key if one is ready. }
function KeyRead(out k: TKey): Boolean;
{ Wait up to ms milliseconds for input to arrive. }
procedure KeyWait(ms: Integer);
procedure KeysFlush;
{ Canonical name of a key, e.g. 'C-K', 'A-x', 'S-F5', 'UP', 'ENTER'; '' for none. }
function KeyName(const k: TKey): string;
{ Inverse of KeyName; code = kcNone if the name is not understood. }
function KeyFromName(const nm: string): TKey;
{ Human readable form in QEdit's style: ^K, @F, #F5 ... }
function KeyLabel(const nm: string): string;

implementation

uses SysUtils, BaseUnix, termio;

const
  BUFSZ = 16384;
  ESC_WAIT_MS = 40;

type
  TParse = (pNeedMore, pKey, pSkip);

var
  buf: array[0..BUFSZ - 1] of Byte;
  bstart, bend: Integer;
  saved: Termios;
  haveSaved: Boolean = False;
  waitSince: QWord = 0;

procedure WriteTty(const s: string);
begin
  if Length(s) > 0 then fpWrite(1, s[1], Length(s));
end;

procedure OnSignal(sig: cint); cdecl;
begin
  Hangup := True;
end;

procedure KeysInit;
var
  t: Termios;
begin
  fpSignal(SIGHUP, @OnSignal);
  fpSignal(SIGTERM, @OnSignal);
  bstart := 0; bend := 0; waitSince := 0;
  if TCGetAttr(0, saved) = 0 then begin
    haveSaved := True;
    t := saved;
    CFMakeRaw(t);
    t.c_cc[VMIN] := 0;
    t.c_cc[VTIME] := 0;
    TCSetAttr(0, TCSANOW, t);
  end;
  WriteTty(#27'[?2004h');            { bracketed paste }
end;

procedure KeysDone;
begin
  WriteTty(#27'[?2004l');
  if haveSaved then TCSetAttr(0, TCSANOW, saved);
end;

procedure Fill;
var
  n: Integer;
begin
  if bstart = bend then begin bstart := 0; bend := 0; end;
  if bend >= BUFSZ then begin
    if bstart = 0 then Exit;
    Move(buf[bstart], buf[0], bend - bstart);
    Dec(bend, bstart);
    bstart := 0;
  end;
  n := fpRead(0, buf[bend], BUFSZ - bend);
  if n > 0 then Inc(bend, n);
end;

procedure KeyWait(ms: Integer);
var
  pfd: tpollfd;
begin
  if bstart < bend then Exit;
  pfd.fd := 0;
  pfd.events := POLLIN;
  pfd.revents := 0;
  fpPoll(@pfd, 1, ms);
  if (pfd.revents and (POLLHUP or POLLERR or POLLNVAL)) <> 0 then Hangup := True;
end;

function LC(c: Char): Char;
begin
  if (c >= 'A') and (c <= 'Z') then Result := Chr(Ord(c) + 32) else Result := c;
end;

function ModsFromParam(v: Integer): TMods;
begin
  Result := [];
  if v < 2 then Exit;
  Dec(v);
  if (v and 1) <> 0 then Include(Result, mShift);
  if (v and 2) <> 0 then Include(Result, mAlt);
  if (v and 4) <> 0 then Include(Result, mCtrl);
end;

function Parse(out k: TKey; out used: Integer): TParse;
var
  avail, i, np, v, need: Integer;
  b0, b1, c, fin: Byte;
  params: array[0..3] of Integer;
  md: TMods;

  function Key(cd: TKeyCode; n: Integer; len: Integer; m: TMods): TParse;
  begin
    k.code := cd;
    k.n := n;
    k.mods := m;
    used := len;
    Result := pKey;
  end;

  function FKey(n, len: Integer; m: TMods): TParse;
  begin
    Result := Key(kcF, n, len, m);
  end;

begin
  k.code := kcNone; k.mods := []; k.ch := ''; k.n := 0; used := 1;
  avail := bend - bstart;
  b0 := buf[bstart];
  if b0 = 27 then begin
    if avail = 1 then Exit(pNeedMore);
    b1 := buf[bstart + 1];
    if b1 = Ord('[') then begin
      if avail = 2 then Exit(pNeedMore);
      c := buf[bstart + 2];
      if c = Ord('[') then begin          { Linux console: ESC [ [ A..E = F1..F5 }
        if avail = 3 then Exit(pNeedMore);
        c := buf[bstart + 3];
        if (c >= Ord('A')) and (c <= Ord('E')) then Exit(FKey(c - Ord('A') + 1, 4, []));
        used := 4;
        Exit(pSkip);
      end;
      np := 0; params[0] := 0; params[1] := 0; params[2] := 0; params[3] := 0;
      i := 2;
      while i < avail do begin
        c := buf[bstart + i];
        if (c >= Ord('0')) and (c <= Ord('9')) then begin
          if np <= 3 then params[np] := params[np] * 10 + (c - Ord('0'));
        end else if c = Ord(';') then begin
          if np < 3 then Inc(np);
        end else if (c >= $40) and (c <= $7E) then begin
          fin := c;
          used := i + 1;
          v := params[0];
          if np >= 1 then md := ModsFromParam(params[1]) else md := [];
          case Chr(fin) of
            'A': Exit(Key(kcUp, 0, used, md));
            'B': Exit(Key(kcDown, 0, used, md));
            'C': Exit(Key(kcRight, 0, used, md));
            'D': Exit(Key(kcLeft, 0, used, md));
            'H': Exit(Key(kcHome, 0, used, md));
            'F': Exit(Key(kcEnd, 0, used, md));
            'Z': Exit(Key(kcTab, 0, used, [mShift]));
            'P': Exit(FKey(1, used, md));
            'Q': Exit(FKey(2, used, md));
            'R': Exit(FKey(3, used, md));
            'S': Exit(FKey(4, used, md));
            '~': begin
              case v of
                1, 7: Exit(Key(kcHome, 0, used, md));
                2: Exit(Key(kcIns, 0, used, md));
                3: Exit(Key(kcDel, 0, used, md));
                4, 8: Exit(Key(kcEnd, 0, used, md));
                5: Exit(Key(kcPgUp, 0, used, md));
                6: Exit(Key(kcPgDn, 0, used, md));
                11..15: Exit(FKey(v - 10, used, md));
                17..21: Exit(FKey(v - 11, used, md));
                23, 24: Exit(FKey(v - 12, used, md));
                { Linux console: Shift+F3..F10 arrive as F13..F20 }
                25, 26: Exit(FKey(v - 22, used, md + [mShift]));
                28, 29: Exit(FKey(v - 23, used, md + [mShift]));
                31..34: Exit(FKey(v - 24, used, md + [mShift]));
                200: Exit(Key(kcPasteBegin, 0, used, []));
                201: Exit(Key(kcPasteEnd, 0, used, []));
              end;
              Exit(pSkip);
            end;
          end;
          Exit(pSkip);        { mouse reports, focus events, unknown keys }
        end else if (c < $20) or (c > $3F) then begin
          { not a CSI sequence: the ESC is a key of its own }
          Exit(Key(kcEsc, 0, 1, []));
        end;
        Inc(i);
      end;
      if avail > 32 then begin used := avail; Exit(pSkip); end;
      Exit(pNeedMore);
    end;
    if b1 = Ord('O') then begin             { SS3: ESC O P..S = F1..F4, arrows }
      if avail = 2 then Exit(pNeedMore);
      c := buf[bstart + 2];
      case Chr(c) of
        'P': Exit(FKey(1, 3, []));
        'Q': Exit(FKey(2, 3, []));
        'R': Exit(FKey(3, 3, []));
        'S': Exit(FKey(4, 3, []));
        'A': Exit(Key(kcUp, 0, 3, []));
        'B': Exit(Key(kcDown, 0, 3, []));
        'C': Exit(Key(kcRight, 0, 3, []));
        'D': Exit(Key(kcLeft, 0, 3, []));
        'H': Exit(Key(kcHome, 0, 3, []));
        'F': Exit(Key(kcEnd, 0, 3, []));
      end;
      k.code := kcChar; k.ch := 'o'; k.mods := [mAlt];
      used := 2;
      Exit(pKey);
    end;
    if (b1 = 127) or (b1 = 8) then Exit(Key(kcBack, 0, 2, [mAlt]));
    if b1 = 13 then Exit(Key(kcEnter, 0, 2, [mAlt]));
    if (b1 >= 33) and (b1 <= 126) then begin  { Alt + a printable key }
      k.code := kcChar; k.ch := LC(Chr(b1)); k.mods := [mAlt];
      used := 2;
      Exit(pKey);
    end;
    Exit(Key(kcEsc, 0, 1, []));
  end;
  case b0 of
    0: begin k.code := kcChar; k.ch := ' '; k.mods := [mCtrl]; Exit(pKey); end;
    13: Exit(Key(kcEnter, 0, 1, []));
    9: Exit(Key(kcTab, 0, 1, []));
    8, 127: Exit(Key(kcBack, 0, 1, []));
    10: begin k.code := kcChar; k.ch := 'j'; k.mods := [mCtrl]; Exit(pKey); end;
    1..7, 11, 12, 14..26: begin
      k.code := kcChar; k.ch := Chr(b0 + 96); k.mods := [mCtrl]; Exit(pKey);
    end;
    28..31: begin
      k.code := kcChar; k.ch := Chr(b0 + 64); k.mods := [mCtrl];
      if b0 = 28 then k.ch := '\' else if b0 = 29 then k.ch := ']'
      else if b0 = 30 then k.ch := '^' else k.ch := '_';
      Exit(pKey);
    end;
    32..126: begin k.code := kcChar; k.ch := Chr(b0); Exit(pKey); end;
    $C2..$F4: begin
      if b0 < $E0 then need := 2 else if b0 < $F0 then need := 3 else need := 4;
      if avail < need then Exit(pNeedMore);
      for i := 1 to need - 1 do
        if (buf[bstart + i] and $C0) <> $80 then begin
          { stray lead byte: pass it through as a single byte }
          k.code := kcChar; k.ch := Chr(b0); used := 1; Exit(pKey);
        end;
      k.code := kcChar;
      SetLength(k.ch, need);
      Move(buf[bstart], k.ch[1], need);
      used := need;
      Exit(pKey);
    end;
    128..193, 245..255: begin k.code := kcChar; k.ch := Chr(b0); Exit(pKey); end;
  end;
  used := 1;
  Result := pSkip;
end;

function KeyRead(out k: TKey): Boolean;
var
  used: Integer;
  r: TParse;
begin
  Result := False;
  k.code := kcNone; k.mods := []; k.ch := ''; k.n := 0;
  Fill;
  repeat
    if bstart >= bend then begin waitSince := 0; Exit; end;
    r := Parse(k, used);
    case r of
      pNeedMore: begin
        if waitSince = 0 then waitSince := GetTickCount64;
        if GetTickCount64 - waitSince < ESC_WAIT_MS then Exit;
        waitSince := 0;
        if (bend - bstart = 2) and (buf[bstart + 1] = Ord('O')) then begin
          k.code := kcChar; k.ch := 'o'; k.mods := [mAlt]; Inc(bstart, 2); Exit(True);
        end;
        if buf[bstart] = 27 then begin
          k.code := kcEsc; Inc(bstart); Exit(True);
        end;
        { an incomplete UTF-8 sequence: pass the bytes through one by one }
        k.code := kcChar; k.ch := Chr(buf[bstart]); Inc(bstart); Exit(True);
      end;
      pKey: begin waitSince := 0; Inc(bstart, used); Exit(True); end;
      pSkip: begin waitSince := 0; Inc(bstart, used); end;
    end;
  until False;
end;

procedure KeysFlush;
begin
  repeat
    Fill;
    if bstart >= bend then Break;
    bstart := bend;
  until False;
  bstart := 0; bend := 0; waitSince := 0;
end;

function KeyName(const k: TKey): string;
var
  p, base: string;
begin
  p := '';
  if mCtrl in k.mods then p := p + 'C-';
  if mAlt in k.mods then p := p + 'A-';
  if mShift in k.mods then p := p + 'S-';
  case k.code of
    kcChar: begin
      if k.ch = ' ' then base := 'SPACE' else base := k.ch;
    end;
    kcUp: base := 'UP';
    kcDown: base := 'DOWN';
    kcLeft: base := 'LEFT';
    kcRight: base := 'RIGHT';
    kcPgUp: base := 'PGUP';
    kcPgDn: base := 'PGDN';
    kcHome: base := 'HOME';
    kcEnd: base := 'END';
    kcIns: base := 'INS';
    kcDel: base := 'DEL';
    kcEnter: base := 'ENTER';
    kcEsc: base := 'ESC';
    kcBack: base := 'BS';
    kcTab: base := 'TAB';
    kcF: base := 'F' + IntToStr(k.n);
  else
    Exit('');
  end;
  { Shift on a plain character is already in the character itself }
  if (k.code = kcChar) and (mShift in k.mods) then Delete(p, Length(p) - 1, 2);
  { C-S- order is fixed: C-, A-, S- }
  Result := p + base;
end;

function KeyFromName(const nm: string): TKey;
var
  s, u: string;
  i: Integer;
begin
  Result.code := kcNone; Result.mods := []; Result.ch := ''; Result.n := 0;
  s := nm;
  while (Length(s) > 2) and (s[2] = '-') and (s[1] in ['C', 'A', 'S']) do begin
    case s[1] of
      'C': Include(Result.mods, mCtrl);
      'A': Include(Result.mods, mAlt);
      'S': Include(Result.mods, mShift);
    end;
    Delete(s, 1, 2);
  end;
  u := UpperCase(s);
  if u = 'UP' then Result.code := kcUp
  else if u = 'DOWN' then Result.code := kcDown
  else if u = 'LEFT' then Result.code := kcLeft
  else if u = 'RIGHT' then Result.code := kcRight
  else if u = 'PGUP' then Result.code := kcPgUp
  else if u = 'PGDN' then Result.code := kcPgDn
  else if u = 'HOME' then Result.code := kcHome
  else if u = 'END' then Result.code := kcEnd
  else if u = 'INS' then Result.code := kcIns
  else if u = 'DEL' then Result.code := kcDel
  else if u = 'ENTER' then Result.code := kcEnter
  else if u = 'ESC' then Result.code := kcEsc
  else if u = 'BS' then Result.code := kcBack
  else if u = 'TAB' then Result.code := kcTab
  else if u = 'SPACE' then begin Result.code := kcChar; Result.ch := ' '; end
  else if (Length(u) >= 2) and (u[1] = 'F') and (Length(u) <= 3) then begin
    i := StrToIntDef(Copy(u, 2, 2), 0);
    if i > 0 then begin Result.code := kcF; Result.n := i; end;
  end;
  if (Result.code = kcNone) and (Length(s) > 0) then begin
    Result.code := kcChar;
    Result.ch := s;
  end;
end;

function KeyLabel(const nm: string): string;
var
  k: TKey;
  b: string;
begin
  k := KeyFromName(nm);
  if k.code = kcNone then Exit(nm);
  case k.code of
    kcChar: b := UpperCase(k.ch);
    kcF: b := 'F' + IntToStr(k.n);
    kcEnter: b := 'Enter';
    kcEsc: b := 'Esc';
    kcBack: b := 'Bksp';
    kcTab: b := 'Tab';
    kcUp: b := 'Up';
    kcDown: b := 'Down';
    kcLeft: b := 'Left';
    kcRight: b := 'Right';
    kcPgUp: b := 'PgUp';
    kcPgDn: b := 'PgDn';
    kcHome: b := 'Home';
    kcEnd: b := 'End';
    kcIns: b := 'Ins';
    kcDel: b := 'Del';
  else
    b := nm;
  end;
  if (mCtrl in k.mods) and (k.code = kcChar) then Exit('^' + b);
  Result := '';
  if mCtrl in k.mods then Result := Result + '^';
  if mAlt in k.mods then Result := Result + '@';
  if mShift in k.mods then Result := Result + '#';
  Result := Result + b;
end;

end.

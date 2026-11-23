program mkedit;
{$mode objfpc}{$H+}
{ MKEDIT - a Linux terminal editor modelled on QEdit 2.x (the DOS "quick editor").
  Free Pascal. Big files are edited through a sliding 64K window. }

uses
  SysUtils, Classes, BaseUnix, termio, Video, uKeys, uApp;

const
  USAGE =
    'mkedit - a QEdit style text editor for the terminal' + LineEnding + LineEnding +
    'usage: mkedit [+LINE] [file | wildcard | directory]...' + LineEnding + LineEnding +
    '  +LINE         start at this line of the first file' + LineEnding +
    '  -V, --version print the version' + LineEnding +
    '  -h, --help    this text' + LineEnding + LineEnding +
    'With no file name mkedit asks for one. Press F1 inside the program for the key list and' + LineEnding +
    'Esc for the menus. Files of any size can be edited: only a window of about 64K is kept in' + LineEnding +
    'memory, the rest is parked in temporary files.';

var
  files: TStringList;
  app: TApp;
  i: Integer;
  a: string;
  gotoLine: Int64;
  failure: string;
begin
  files := TStringList.Create;
  gotoLine := 0;
  for i := 1 to ParamCount do begin
    a := ParamStr(i);
    if (a = '-h') or (a = '--help') or (a = '-?') then begin
      WriteLn(USAGE);
      Halt(0);
    end else if (a = '-V') or (a = '--version') then begin
      WriteLn('mkedit ', VERSION, ' (Free Pascal)');
      Halt(0);
    end else if (Length(a) > 1) and (a[1] = '+') and (StrToInt64Def(Copy(a, 2, MaxInt), -1) >= 0) then
      gotoLine := StrToInt64Def(Copy(a, 2, MaxInt), 0)
    else
      files.Add(a);
  end;
  if (IsATTY(0) = 0) or (IsATTY(1) = 0) then begin
    WriteLn(StdErr, 'mkedit: standard input and output must be a terminal');
    Halt(1);
  end;
  failure := '';
  app := TApp.Create;
  InitVideo;
  KeysInit;
  try
    try
      app.LoadConfig;
      app.Start(files, gotoLine);
      app.Run;
    except
      on E: EHangup do begin
        app.EmergencySave;
        failure := 'terminal lost; unsaved work was kept as NAME.mkedit-save';
      end;
      on E: Exception do failure := E.ClassName + ': ' + E.Message;
    end;
  finally
    KeysDone;
    DoneVideo;
  end;
  app.Free;
  files.Free;
  if failure <> '' then begin
    WriteLn(StdErr, 'mkedit: ', failure);
    Halt(2);
  end;
  Write(#27'[2J'#27'[H');
end.

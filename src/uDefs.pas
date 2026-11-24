unit uDefs;
{$mode objfpc}{$H+}
{ Commands, default key bindings, menus and the help screen contents.
  Key names are those of uKeys.KeyName: 'C-k' is Ctrl-K, 'A-c' is Alt-C, 'S-F5' is Shift-F5.
  A binding may be a sequence of two keys, e.g. 'C-k b' (Ctrl-K then B). }

interface

uses Classes;

type
  TCmd = (
    cmNone,
    { cursor }
    cmBegFile, cmBegLine, cmBegScreen, cmCursorDown, cmCursorLeft, cmCursorRight, cmCursorUp,
    cmEndFile, cmEndLine, cmEndScreen, cmGotoBlockBeg, cmGotoBlockEnd, cmGotoLine, cmHalfPgDn,
    cmHalfPgUp, cmLineDown, cmLineUp, cmMakeBotofScreen, cmMakeCtrofScreen, cmMakeTopofScreen,
    cmPageDown, cmPageUp, cmPrevPosition, cmScreenLeft, cmScreenRight, cmScrollDown, cmScrollUp,
    cmWordLeft, cmWordRight,
    { editing }
    cmAddLine, cmAlign, cmBackspace, cmDelCh, cmDelLine, cmDelLtWord, cmDelRtWord, cmDelToEol,
    cmDupLine, cmGetPrev, cmInsertLine, cmJoinLine, cmLiteral, cmReturn, cmSplitLine, cmUnKill,
    { blocks and buffers }
    cmAppendScrbuff, cmCopy, cmCopyBlock, cmCopyOverBlock, cmCut, cmDeleteBlock, cmDropAnchor,
    cmGetScrbuff, cmMarkBlockBegin, cmMarkBlockEnd, cmMarkCharacter, cmMarkColumn, cmMarkLine,
    cmMoveBlock, cmPaste, cmPasteOver, cmShiftLeft, cmShiftRight, cmStoreScrbuff, cmUnmarkBlock,
    { files }
    cmChangeFilename, cmEditFile, cmExit, cmFile, cmGExit, cmGFile, cmGPQuit, cmGSave, cmKillFile,
    cmNextFile, cmPQuit, cmPrevFile, cmQuit, cmReadBlock, cmSaveFile, cmWriteBlock,
    { windows }
    cmCloseWindow, cmGrowWindow, cmHorizontalWindow, cmNextWindow, cmOneWindow, cmPrevWindow,
    cmShrinkWindow, cmZoomWindow,
    { macros }
    cmExecuteScrap, cmMacroRead, cmMacroRecord, cmMacroWrite,
    { printing }
    cmPrintAll, cmPrintBlock, cmPrintEject, cmSetPrintLeftMargin, cmSetPrintPageSize,
    { tabs }
    cmSetCtabwidth, cmSetPtabwidth, cmTabLt, cmTabRt,
    { search }
    cmFind, cmFindReplace, cmRepeatFind,
    { toggles }
    cmToggleBakups, cmToggleBoxDraw, cmToggleEnterMatching, cmToggleIndent, cmToggleInsert,
    cmToggleSmartTabs, cmToggleTabsExpand, cmToggleTabsOut, cmToggleWordwrap,
    { other }
    cmDos, cmMainMenu, cmCurrentFilename, cmColors, cmInsertDate, cmInsertTime, cmMatch, cmQuickHelp, cmSetRmargin, cmShell,
    cmUndoCursorline, cmWrapPara,
    { open a particular pull-down menu directly (Alt-F, Alt-Q, Alt-P) }
    cmMenuFile, cmMenuQuit, cmMenuPrint
  );

const
  CmdNames: array[TCmd] of string = (
    '',
    'BegFile', 'BegLine', 'BegScreen', 'CursorDown', 'CursorLeft', 'CursorRight', 'CursorUp',
    'EndFile', 'EndLine', 'EndScreen', 'GotoBlockBeg', 'GotoBlockEnd', 'GotoLine', 'HalfPgDn',
    'HalfPgUp', 'LineDown', 'LineUp', 'MakeBotofScreen', 'MakeCtrofScreen', 'MakeTopofScreen',
    'PageDown', 'PageUp', 'PrevPosition', 'ScreenLeft', 'ScreenRight', 'ScrollDown', 'ScrollUp',
    'WordLeft', 'WordRight',
    'AddLine', 'Align', 'Backspace', 'DelCh', 'DelLine', 'DelLtWord', 'DelRtWord', 'DelToEol',
    'DupLine', 'GetPrev', 'InsertLine', 'JoinLine', 'Literal', 'Return', 'SplitLine', 'UnKill',
    'AppendScrbuff', 'Copy', 'CopyBlock', 'CopyOverBlock', 'Cut', 'DeleteBlock', 'DropAnchor',
    'GetScrbuff', 'MarkBlockBegin', 'MarkBlockEnd', 'MarkCharacter', 'MarkColumn', 'MarkLine',
    'MoveBlock', 'Paste', 'PasteOver', 'ShiftLeft', 'ShiftRight', 'StoreScrbuff', 'UnmarkBlock',
    'ChangeFilename', 'EditFile', 'Exit', 'File', 'GExit', 'GFile', 'GPQuit', 'GSave', 'KillFile',
    'NextFile', 'PQuit', 'PrevFile', 'Quit', 'ReadBlock', 'SaveFile', 'WriteBlock',
    'CloseWindow', 'GrowWindow', 'HorizontalWindow', 'NextWindow', 'OneWindow', 'PrevWindow',
    'ShrinkWindow', 'ZoomWindow',
    'ExecuteScrap', 'MacroRead', 'MacroRecord', 'MacroWrite',
    'PrintAll', 'PrintBlock', 'PrintEject', 'SetPrintLeftMargin', 'SetPrintPageSize',
    'SetCtabwidth', 'SetPtabwidth', 'TabLt', 'TabRt',
    'Find', 'FindReplace', 'RepeatFind',
    'ToggleBakups', 'ToggleBoxDraw', 'ToggleEnterMatching', 'ToggleIndent', 'ToggleInsert',
    'ToggleSmartTabs', 'ToggleTabsExpand', 'ToggleTabsOut', 'ToggleWordwrap',
    'Dos', 'MainMenu', 'CurrentFilename', 'Colors', 'InsertDate', 'InsertTime', 'Match', 'QuickHelp', 'SetRmargin', 'Shell',
    'UndoCursorline', 'WrapPara',
    'MenuFile', 'MenuQuit', 'MenuPrint'
  );

const
  { The prefix keys of the two-key (WordStar style) commands }
  Prefixes: array[0..3] of string = ('C-k', 'C-q', 'C-o', 'C-b');

  
type
  TMenuItem = record
    hot: Char;
    text: string;
    cmd: TCmd;
  end;
  TMenu = record
    title: string;
    hot: Char;
    items: array of TMenuItem;
  end;

var
  Menus: array of TMenu;

{ Fills list with 'keys=cmdname' pairs (Objects[] hold the TCmd) }
procedure DefaultBindings(list: TStrings);
function CmdByName(const nm: string): TCmd;

{ Help screen text. Each section is: title, then rows 'label|keys'. }
const
  HelpBlock: array[0..11] of string = (
    'copy block|@c, ^kc', 'drop anchor|@a', 'mark block begin|f7, ^kb', 'mark block end|f8, ^kk',
    'mark line|@l', 'move block|@m, ^kv', 'read block|@r, ^kr', 'unmark block|@u, ^kh',
    'writeblock|@w, ^kw', 'delete block|@g, ^ky', 'mark column|@k', 'copy/cut/paste|^ins #del #ins');
  HelpEdit: array[0..11] of string = (
    'add line|f2', 'del line|@d, ^y', 'del rt word|^t', 'del to eol|f6, ^qy', 'dup line|f4',
    'insert line|@f2', 'join line|@j', 'literal|^p', 'split line|@s, ^n', 'undo cursorline|^ql',
    'unkill|^u', 'wrap para|@b');
  HelpCursor1: array[0..9] of string = (
    'goto block beg|^qb', 'goto line|^j', 'page down|^c', 'prev position|^qp', 'page up|^r',
    'screen right|@f6', 'scroll up|^w', 'shiftright|#f8', 'word right|^f', 'MakeTopOfScreen|f5');
  HelpCursor2: array[0..9] of string = (
    'goto block end|^qk', 'MakeCtrOfScreen|#f5', 'screen left|@f5', 'scroll down|^z',
    'shiftleft|#f7', 'word left|^a', 'begin file|^pgup', 'end file|^pgdn', 'word wrap|^ow',
    'right margin|^or');
  HelpFiles: array[0..11] of string = (
    'change filename|@o, ^kf', 'edit file|@e, ^ke', 'exit|^kd', 'file|^kx', 'global exit|@x',
    'next file|@n, ^kn', 'os|@f9', 'pquit|^kq', 'prev file|^kp', 'save file|^ks', 'shell|f9',
    'kill file|^kz');
  HelpWindows: array[0..7] of string = (
    'close window|^oc', 'grow window|^og', 'Split Window|^oh', 'next window|^on', 'one window|^oo',
    'prev window|^op', 'shrink window|^os', 'zoom window|^oz');
  HelpSearch: array[0..3] of string = (
    'find|^qf', 'find replace|^qa', 'match|@f3', 'repeat find|^l');
  HelpMacro: array[0..1] of string = (
    'Macro Record|f12, ^om', 'Execute scrap|f11');

implementation

uses SysUtils;

procedure DefaultBindings(list: TStrings);

  procedure Bind(const k: string; c: TCmd);
  begin
    list.AddObject(k, TObject(PtrInt(Ord(c))));
  end;

begin
  Bind('UP', cmCursorUp);
  Bind('DOWN', cmCursorDown);
  Bind('LEFT', cmCursorLeft);
  Bind('RIGHT', cmCursorRight);
  Bind('C-e', cmCursorUp);
  Bind('C-x', cmCursorDown);
  Bind('C-s', cmCursorLeft);
  Bind('C-d', cmCursorRight);
  Bind('HOME', cmBegLine);
  Bind('END', cmEndLine);
  Bind('C-q s', cmBegLine);
  Bind('C-q d', cmEndLine);
  Bind('PGUP', cmPageUp);
  Bind('PGDN', cmPageDown);
  Bind('C-r', cmPageUp);
  Bind('C-c', cmPageDown);
  Bind('C-PGUP', cmBegFile);
  Bind('C-PGDN', cmEndFile);
  Bind('C-q r', cmBegFile);
  Bind('C-q c', cmEndFile);
  Bind('C-HOME', cmBegScreen);
  Bind('C-END', cmEndScreen);
  Bind('C-q e', cmBegScreen);
  Bind('C-q x', cmEndScreen);
  Bind('C-LEFT', cmWordLeft);
  Bind('C-RIGHT', cmWordRight);
  Bind('C-a', cmWordLeft);
  Bind('C-f', cmWordRight);
  Bind('C-q b', cmGotoBlockBeg);
  Bind('C-q k', cmGotoBlockEnd);
  Bind('C-j', cmGotoLine);
  Bind('C-q p', cmPrevPosition);
  Bind('C-w', cmScrollUp);
  Bind('C-z', cmScrollDown);
  Bind('A-F5', cmScreenLeft);
  Bind('A-F6', cmScreenRight);
  Bind('F5', cmMakeTopofScreen);
  Bind('S-F5', cmMakeCtrofScreen);
  Bind('F2', cmAddLine);
  Bind('A-F2', cmInsertLine);
  Bind('BS', cmBackspace);
  Bind('A-BS', cmDelLtWord);
  Bind('DEL', cmDelCh);
  Bind('C-g', cmDelCh);
  Bind('A-d', cmDelLine);
  Bind('C-y', cmDelLine);
  Bind('C-t', cmDelRtWord);
  Bind('F6', cmDelToEol);
  Bind('C-q y', cmDelToEol);
  Bind('F4', cmDupLine);
  Bind('C-_', cmGetPrev);
  Bind('A-j', cmJoinLine);
  Bind('C-p', cmLiteral);
  Bind('ENTER', cmReturn);
  Bind('A-s', cmSplitLine);
  Bind('C-n', cmSplitLine);
  Bind('C-u', cmUnKill);
  Bind('C-q l', cmUndoCursorline);
  Bind('TAB', cmTabRt);
  Bind('S-TAB', cmTabLt);
  Bind('A-c', cmCopyBlock);
  Bind('C-k c', cmCopyBlock);
  Bind('A-z', cmCopyOverBlock);
  Bind('A-g', cmDeleteBlock);
  Bind('C-k y', cmDeleteBlock);
  Bind('A-a', cmDropAnchor);
  Bind('F7', cmMarkBlockBegin);
  Bind('C-k b', cmMarkBlockBegin);
  Bind('F8', cmMarkBlockEnd);
  Bind('C-k k', cmMarkBlockEnd);
  Bind('A-k', cmMarkColumn);
  Bind('A-l', cmMarkLine);
  Bind('A-m', cmMoveBlock);
  Bind('C-k v', cmMoveBlock);
  Bind('A-u', cmUnmarkBlock);
  Bind('C-k h', cmUnmarkBlock);
  Bind('S-F7', cmShiftLeft);
  Bind('S-F8', cmShiftRight);
  Bind('C-INS', cmCopy);
  Bind('S-DEL', cmCut);
  Bind('S-INS', cmPaste);
  Bind('C-b s', cmStoreScrbuff);
  Bind('C-b a', cmAppendScrbuff);
  Bind('C-b l', cmGetScrbuff);
  Bind('A-o', cmChangeFilename);
  Bind('C-k f', cmChangeFilename);
  Bind('A-e', cmEditFile);
  Bind('C-k e', cmEditFile);
  Bind('C-k d', cmExit);
  Bind('C-k x', cmFile);
  Bind('A-x', cmGExit);
  Bind('A-y', cmGSave);
  Bind('F3', cmGPQuit);
  Bind('A-n', cmNextFile);
  Bind('C-k n', cmNextFile);
  Bind('C-k p', cmPrevFile);
  Bind('C-k q', cmPQuit);
  Bind('A-r', cmReadBlock);
  Bind('C-k r', cmReadBlock);
  Bind('C-k s', cmSaveFile);
  Bind('A-w', cmWriteBlock);
  Bind('C-k w', cmWriteBlock);
  Bind('C-k z', cmKillFile);
  Bind('C-o c', cmCloseWindow);
  Bind('C-o g', cmGrowWindow);
  Bind('C-o h', cmHorizontalWindow);
  Bind('C-o n', cmNextWindow);
  Bind('C-o o', cmOneWindow);
  Bind('C-o p', cmPrevWindow);
  Bind('C-o s', cmShrinkWindow);
  Bind('C-o z', cmZoomWindow);
  Bind('F12', cmMacroRecord);
  Bind('C-o m', cmMacroRecord);
  Bind('F11', cmExecuteScrap);
  Bind('C-q f', cmFind);
  Bind('C-q a', cmFindReplace);
  Bind('C-l', cmRepeatFind);
  Bind('A-F3', cmMatch);
  Bind('S-F1', cmToggleBoxDraw);
  Bind('C-q i', cmToggleIndent);
  Bind('C-q t', cmToggleSmartTabs);
  Bind('A-v', cmToggleTabsExpand);
  Bind('A-i', cmToggleTabsOut);
  Bind('INS', cmToggleInsert);
  Bind('C-v', cmToggleInsert);
  Bind('C-o w', cmToggleWordwrap);
  Bind('C-o r', cmSetRmargin);
  Bind('F1', cmQuickHelp);
  Bind('A-h', cmQuickHelp);
  Bind('ESC', cmMainMenu);
  Bind('F9', cmShell);
  Bind('A-F9', cmDos);
  Bind('A-b', cmWrapPara);
  Bind('A-f', cmMenuFile);
  Bind('A-q', cmMenuQuit);
  Bind('A-p', cmMenuPrint);
end;

function CmdByName(const nm: string): TCmd;
var
  c: TCmd;
begin
  for c := Low(TCmd) to High(TCmd) do
    if SameText(CmdNames[c], nm) then Exit(c);
  Result := cmNone;
end;

procedure AddMenu(const title, hot: string);
begin
  SetLength(Menus, Length(Menus) + 1);
  Menus[High(Menus)].title := title;
  Menus[High(Menus)].hot := hot[1];
end;

procedure AddItem(const AHot, AText: string; c: TCmd);
var
  m: Integer;
begin
  m := High(Menus);
  SetLength(Menus[m].items, Length(Menus[m].items) + 1);
  with Menus[m].items[High(Menus[m].items)] do begin
    hot := AHot[1]; text := AText; cmd := c;
  end;
end;

initialization
  AddMenu('File', 'F');
  AddItem('C', 'Change filename', cmChangeFilename);
  AddItem('L', 'Edit file', cmEditFile);
  AddItem('N', 'Next file', cmNextFile);
  AddItem('P', 'Prev file', cmPrevFile);
  AddItem('S', 'Save file', cmSaveFile);
  AddItem('F', 'File (save and close)', cmFile);
  AddItem('E', 'Exit (close file)', cmExit);
  AddItem('Q', 'PQuit (close, no save)', cmPQuit);
  AddItem('G', 'GFile (save all, exit)', cmGFile);
  AddItem('R', 'Read block', cmReadBlock);
  AddItem('W', 'Write block', cmWriteBlock);
  AddItem('K', 'Kill file (delete)', cmKillFile);
  AddItem('O', 'Shell', cmShell);
  AddItem('D', 'Dos command', cmDos);
  AddMenu('Block', 'B');
  AddItem('B', 'Mark block begin', cmMarkBlockBegin);
  AddItem('E', 'Mark block end', cmMarkBlockEnd);
  AddItem('L', 'Mark line', cmMarkLine);
  AddItem('A', 'Drop anchor', cmDropAnchor);
  AddItem('K', 'Mark column', cmMarkColumn);
  AddItem('U', 'Unmark block', cmUnmarkBlock);
  AddItem('C', 'Copy block', cmCopyBlock);
  AddItem('M', 'Move block', cmMoveBlock);
  AddItem('D', 'Delete block', cmDeleteBlock);
  AddItem('Y', 'Copy to scrap', cmCopy);
  AddItem('T', 'Cut to scrap', cmCut);
  AddItem('P', 'Paste scrap', cmPaste);
  AddItem('O', 'Paste over', cmPasteOver);
  AddItem('S', 'Store scratch buffer', cmStoreScrbuff);
  AddItem('G', 'Get scratch buffer', cmGetScrbuff);
  AddMenu('Edit', 'E');
  AddItem('A', 'Add line', cmAddLine);
  AddItem('I', 'Insert line', cmInsertLine);
  AddItem('D', 'Delete line', cmDelLine);
  AddItem('E', 'Delete to end of line', cmDelToEol);
  AddItem('J', 'Join line', cmJoinLine);
  AddItem('S', 'Split line', cmSplitLine);
  AddItem('U', 'Unkill', cmUnKill);
  AddItem('P', 'Duplicate line', cmDupLine);
  AddItem('L', 'Undo cursor line', cmUndoCursorline);
  AddItem('W', 'Wrap paragraph', cmWrapPara);
  AddItem('T', 'Insert date and time', cmInsertDate);
  AddItem('N', 'Insert file name', cmCurrentFilename);
  AddMenu('Search', 'S');
  AddItem('F', 'Find', cmFind);
  AddItem('R', 'Find and replace', cmFindReplace);
  AddItem('A', 'Repeat find', cmRepeatFind);
  AddItem('M', 'Match bracket', cmMatch);
  AddMenu('Window', 'W');
  AddItem('S', 'Split window', cmHorizontalWindow);
  AddItem('N', 'Next window', cmNextWindow);
  AddItem('P', 'Prev window', cmPrevWindow);
  AddItem('C', 'Close window', cmCloseWindow);
  AddItem('O', 'One window', cmOneWindow);
  AddItem('Z', 'Zoom window', cmZoomWindow);
  AddItem('G', 'Grow window', cmGrowWindow);
  AddItem('R', 'Shrink window', cmShrinkWindow);
  AddMenu('Options', 'O');
  AddItem('I', 'Insert mode', cmToggleInsert);
  AddItem('A', 'Auto indent', cmToggleIndent);
  AddItem('W', 'Word wrap', cmToggleWordwrap);
  AddItem('R', 'Right margin', cmSetRmargin);
  AddItem('B', 'Backup files', cmToggleBakups);
  AddItem('E', 'Enter matching', cmToggleEnterMatching);
  AddItem('D', 'Box drawing', cmToggleBoxDraw);
  AddItem('S', 'Smart tabs', cmToggleSmartTabs);
  AddItem('T', 'Tab expansion', cmToggleTabsExpand);
  AddItem('U', 'Tabs out', cmToggleTabsOut);
  AddItem('P', 'Physical tab width', cmSetPtabwidth);
  AddItem('C', 'C tab width', cmSetCtabwidth);
  AddItem('L', 'Colors', cmColors);
  AddItem('H', 'Help', cmQuickHelp);
  AddMenu('Macro', 'M');
  AddItem('M', 'Record macro', cmMacroRecord);
  AddItem('X', 'Execute scrap macro', cmExecuteScrap);
  AddItem('R', 'Read macro file', cmMacroRead);
  AddItem('W', 'Write macro file', cmMacroWrite);
  AddMenu('Print', 'P');
  AddItem('A', 'Print all', cmPrintAll);
  AddItem('B', 'Print block', cmPrintBlock);
  AddItem('F', 'Form feed', cmPrintEject);
  AddItem('L', 'Left margin', cmSetPrintLeftMargin);
  AddItem('P', 'Page size', cmSetPrintPageSize);
  AddMenu('Quit', 'Q');
  AddItem('X', 'GExit (ask, exit all)', cmGExit);
  AddItem('Q', 'GPQuit (warn, exit all)', cmGPQuit);
  AddItem('S', 'GSave (save all)', cmGSave);
  AddItem('U', 'Quit (discard file)', cmQuit);

end.

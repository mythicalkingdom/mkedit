# mkedit (Free Pascal)

A Linux terminal editor that follows **QEdit 2.x** (the DOS "quick editor"; its manual is not part of this repository): the same key assignments (Alt/Ctrl/function keys and the `^K ^Q ^O ^B`
two-key commands), the same pull-down menus on Esc, the same status line, block types, kill buffer,
scrap and scratch buffers, macros, windows and file ring. Like its sibling `mklist` it only ever
keeps a **sliding 64K window** of a file in memory, so files of any size can be edited.

    make                              # needs fpc 3.2+; produces build/mkedit
    make install PREFIX=$HOME/.local  # ~/.local/bin/mkedit
    make doctest                      # stress test of the sliding buffer (no terminal needed)
    make test                         # behavioural tests on a pty (python3 + `pip install pyte`)
    build/mkedit [+LINE] [file | wildcard | directory]...

`mkedit file 125` (or `file 125` at the prompt) starts at line 125. With no file name it asks for one (`File(s) to edit:`); wildcards and directories bring up a pick
list. **F1** shows the key list (laid out like QEdit's help screen), **Esc** the menus.

## How big files work

`src/uDoc.pas` holds a file as a window of about 64 KB of lines (`First` = absolute number of the first
line in memory). Lines before the window are parked in a *head* temp file, in 16 KB chunks; lines after
it are either parked in a *tail* temp file (text that was pushed back out, edits included) or still
unread in the original file. `Seek(line)` slides the window, reading a chunk at one end and parking
one at the other; whole chunks are moved between the two stacks without parsing them for long jumps.
Edits only touch lines in the window; cursors and block marks are absolute line numbers ("anchors")
that the document adjusts on every insert/delete. A second window on the same file far from the first
makes the window grow (up to 16 MB) so that both views stay in memory.

Saving streams head, window, tail and the *unread rest of the original, byte for byte* to
`NAME.mkedit-PID.tmp`, then renames it over the file (symlinks are followed, permissions kept,
`NAME.bak` made first if backups are on). Lines that were never visited are therefore never touched.
The saved file then becomes the source, so you can go on editing.

Measured on a 200 MB / 3 million line file: 1.3 MB resident on opening, 2 MB after reading the whole
file, ~1 s to scan to the end, ~25 ms for a random jump, <1 s to save.
Temp files go to `$MKEDIT_TMP`, `$TMPDIR`, `/var/tmp` or `/tmp` (first usable one); they are removed on exit.

## Keys

The QEdit help screen's keys are all there (`@` = Alt, `^` = Ctrl, `#` = Shift):

| | |
|---|---|
| cursor | arrows, Home/End, PgUp/PgDn, `^PgUp/^PgDn` file begin/end, `^Home/^End` screen top/bottom, `^Left/^Right` or `^A/^F` words, `^J` goto line, `^QP` previous position, `^W/^Z` scroll, `F5`/`#F5` line to top/centre, `@F5/@F6` screen left/right, `^E ^X ^S ^D ^R ^C` WordStar diamond |
| block | `@L` line, `@A` anchor (stream), `@K` column, `F7/F8` or `^KB/^KK` begin/end, `@U` or `^KH` unmark, `@C` copy, `@M` move, `@G` delete, `@Z` copy over (column), `#F7/#F8` shift, `@R/@W` read/write file, `^BS ^BA ^BL` scratch buffers |
| scrap | `^Ins` copy, `#Del` cut, `#Ins` paste (no keypad +, -, * on a terminal); Cut/Copy act on the cursor line when no block is marked |
| edit | `F2` add line, `@F2` insert line, `F4` duplicate, `@D`/`^Y` delete line, `F6`/`^QY` to end of line, `^T` word, `@J` join, `@S`/`^N` split, `^U` unkill, `^QL` undo cursor line, `^P` literal, `^_` (Ctrl-minus) copy char from above, `@B` wrap paragraph |
| files | `@E`/`^KE` edit, `@N`/`^KN` next, `^KP` previous, `^KS` save, `^KD` exit, `^KX` file, `^KQ` pquit, `@X` global exit, `@Y` save all, `F3` global pquit, `@O` change name, `^KZ` kill file, `F9` shell, `@F9` run a command |
| windows | `^OH` split, `^ON/^OP` next/previous, `^OG/^OS` grow/shrink (arrow keys, any other key ends), `^OZ` zoom, `^OC` close, `^OO` one |
| search | `^QF` find, `^QA` find and replace (`Y/N/O/G/Q`), `^L` repeat, `@F3` match bracket; options `I` ignore case, `W` words, `B` backward, `N` no ask |
| modes | `Ins`, `^QI` auto indent, `^OW` word wrap, `^OR` right margin, `#F1` box drawing, `^QT` smart tabs, `@V` tab expansion, `@I` tabs out; `Esc O E` enter matching |
| menus | `Esc`, then the capital letter of the menu and of the item (`Esc F S` saves); `@F`, `@Q`, `@P` open File/Quit/Print directly |

Things a terminal cannot do, and what replaces them: **Ctrl-M is Enter**, so macro recording is
`F12` (or `^OM`); *ExecuteScrap* (Ctrl-Enter) is `F11`. Alt+key is Esc+key, so some terminals need
"Alt sends Escape" turned on. Shift/Ctrl/Alt with F-keys and arrows use xterm sequences.

Macros are keystrokes: `F12`, press the key to assign (an unassigned key; Enter = scrap), type the
keys, `F12` again. `Esc M W` / `Esc M R` save and load macro files (plain text).

## Configuration

Colours can be edited live: `Esc O L` (Options, Colors) lets you pick an item, change foreground (Left/Right) and
background (PgUp/PgDn) with the result showing at once, `S` to save them into the config file, Esc to cancel.

`~/.config/mkedit/mkedit.cfg` (or `$XDG_CONFIG_HOME`), `#` comments:

    insert = on             autoindent = on          wordwrap = off
    backup = on             entermatching = off      smarttabs = off
    expandtabs = auto       # auto | on | off, see below
    tabsout = off           cutcopyline = on         lineblockbefore = on
    trimblanks = on         eofmarker = on           lastfileprompt = on
    delchjoin = on          returnsplit = on         delrtwordblanks = on
    findoptions = I         replaceoptions = I       killbuffer = 30
    extensions = .c .h      # tried in turn for a name that does not exist and has no dot
    rmargin = 76            tabwidth = 8             ctabwidth = 4        screenstep = 8
    color_text = 7,1        # fg 0-15, bg 0-7; also _block _status _statusoff _menu _menuselect _box _message
    key F9 = DupLine        # rebind; two-key sequences too: key C-k a = DropAnchor
    key A-d = none          # unbind
    key A-t = MacroBegin EditFile 'notes.txt' Return    # QCONFIG style key macro: commands and 'text'

## Differences from QEdit

* **Tabs.** QEdit expands tabs when loading. Doing that to every file would rewrite tab-indented
  sources on save, so by default (`expandtabs = auto`) a file that already contains tabs (and
  makefiles, `.tsv`, and anything with a NUL byte) keeps its tabs byte for byte and the Tab key inserts
  a tab character; any other file behaves like QEdit (tabs become blanks, Tab inserts blanks).
* **Text encoding.** UTF-8 is understood: a multi-byte character is one column and one cursor step.
  Anything that is not valid UTF-8 is shown as a CP437 character, so binary files round-trip.
  The screen layer (FPC `Video`) is CP437, so characters that CP437 lacks (CJK, emoji) show as `?`.
* **Macros** are recorded as key presses (as in QEdit) but there is no `QCONFIG` program; use the
  config file for keys and colours.
* Line blocks go *after* the cursor line, as in QEdit (`lineblockbefore = on` for above).
* When the last file is closed (`^KD`, `^KX`, `^KQ`) mkedit asks for another one, as QEdit does by default; Esc leaves (`lastfileprompt = off` to quit at once). The menu's Quit asks before discarding changes.
* **KillFile** (`^KZ`) deletes the file from disk but leaves it loaded and marked changed.
* Trailing blanks are removed from lines you edited when the cursor leaves them (`trimblanks = off`).
* **DeleteBlock** puts the whole block in the kill buffer as one entry; the kill buffer holds 30 entries per file.
* Scrap and scratch buffers, and blocks read with `@R`, live in memory (a block of hundreds of MB
  should be written with `@W` rather than copied).
* A terminal hang-up (or SIGHUP/SIGTERM) keeps unsaved work as `NAME.mkedit-save`.
* Not implemented from QEdit's QCONFIG options: status line at the bottom / fill character / boxed display, cursor-line colour, per-extension tab widths, custom help screen file, formfeed after printing, prompt-for-file on new window, close-window-on-quit, Ctrl-Z terminator, Alt-numeric-keypad codes, EGA/VGA mode switching, entry screen, `WSKEY.DAT`/`BRIEF.DAT` style key files, pasting multi-megabyte scraps from outside (bracketed paste works).

## Tests

`tests/doctest.pas` is a randomized model test of the sliding buffer (jumps, inserts, deletes, saves
and continued editing against an in-memory reference; LF, CRLF, no final newline, tiny and big files).
`tests/run_tests.py` drives the real program on a pseudo-terminal and checks what ends up on disk and
on the screen (`-k NAME` selects tests, `-v` prints the screen on failure).

## Source map

| file | |
|---|---|
| `src/mkedit.pas` | start-up, command line |
| `src/uApp.pas` + `app_*.inc` | the editor: windows, drawing, keys; `app_edit` typing/line commands, `app_block` blocks and buffers, `app_files` files/windows/macros/print, `app_search`, `app_ui` prompts/menus/help/dispatch |
| `src/uDoc.pas` | sliding-buffer document, temp-file chunk stacks, saving |
| `src/uDefs.pas` | command list, default key bindings, menus, help text |
| `src/uKeys.pas` | key decoder (modifiers, UTF-8, bracketed paste, hang-up) |
| `src/uText.pas` | UTF-8/tab aware column ↔ index helpers |
| `src/uScreen.pas`, `uCP437.pas` | cell buffer over FPC `Video` (from mklist) |

## License

GPL-3.0-or-later, see `LICENSE`.

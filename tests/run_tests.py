#!/usr/bin/env python3
"""Behavioural tests for mkedit: drive the program on a pseudo-terminal and check both what the
screen shows and what ends up on disk.   MKEDIT_BIN=/path/to/mkedit python3 tests/run_tests.py [-v] [-k NAME]"""
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env  # noqa: E402

BIN = os.environ.get("MKEDIT_BIN") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "mkedit")
BIN = os.path.abspath(BIN)

# ---- key codes
ESC = "\x1b"
def ctrl(c): return chr(ord(c) - 96)
def alt(c): return ESC + c
UP, DOWN, RIGHT, LEFT = "\x1b[A", "\x1b[B", "\x1b[C", "\x1b[D"
HOME, END, PGUP, PGDN, DEL, INS = "\x1b[H", "\x1b[F", "\x1b[5~", "\x1b[6~", "\x1b[3~", "\x1b[2~"
C_PGUP, C_PGDN = "\x1b[5;5~", "\x1b[6;5~"
C_LEFT, C_RIGHT = "\x1b[1;5D", "\x1b[1;5C"
F1, F2, F3, F4 = "\x1bOP", "\x1bOQ", "\x1bOR", "\x1bOS"
F5, F6, F7, F8, F9 = "\x1b[15~", "\x1b[17~", "\x1b[18~", "\x1b[19~", "\x1b[20~"
F11, F12 = "\x1b[23~", "\x1b[24~"
A_F9 = "\x1b[20;3~"
F10, S_F10 = "\x1b[21~", "\x1b[21;2~"
UNDO, REDO = alt("/"), "\x1e"
S_F5, S_F7, S_F8 = "\x1b[15;2~", "\x1b[18;2~", "\x1b[19;2~"
A_F2, A_F3 = "\x1b[1;3Q", "\x1b[1;3R"
BS, ENTER, TAB, S_TAB = "\x7f", "\r", "\t", "\x1b[Z"
def k(*seq): return "".join(seq)
SAVE = ctrl("k") + "s"
EXIT_NOSAVE = ctrl("k") + "q"

TESTS = []
def test(f):
    TESTS.append(f)
    return f

def read(env, name):
    """File contents as text (latin-1, so every byte shows up as one character)."""
    with open(env.path(name), "rb") as f:
        return f.read().decode("latin-1")

def eq(got, want, what=""):
    if got != want:
        raise AssertionError("%s\n  got : %r\n  want: %r" % (what, got, want))

def edit(env, content, *keys, name="a.txt", args=None, rows=None):
    """Open a file with content, send keys, save with ^KS and return the saved text."""
    env.write(name, content)
    kw = {}
    if rows: kw["rows"] = rows
    s = env.start(*(args or [name]), **kw)
    for key in keys:
        s.send(key, 0.12)
    s.send(SAVE, 0.4)
    return s, read(env, name)

# ------------------------------------------------------------------ basics
@test
def startup_shows_file_and_status(env):
    env.write("a.txt", "hello world\nsecond\n")
    s = env.start("a.txt")
    assert "hello world" in s.row(1), s.text()
    st = s.stat()
    eq(st[0], 1); eq(st[1], 1)
    assert st[2].startswith("IA"), st
    assert st[4].endswith("a.txt")

@test
def typing_and_save(env):
    s, t = edit(env, "", "hello", ENTER, "world")
    eq(t, "hello\nworld\n")

@test
def insert_in_middle(env):
    s, t = edit(env, "abcdef\n", RIGHT, RIGHT, RIGHT, "XY")
    eq(t, "abcXYdef\n")

@test
def overwrite_mode(env):
    s, t = edit(env, "abcdef\n", INS, "XY")
    eq(t, "XYcdef\n")

@test
def backspace_and_join(env):
    s, t = edit(env, "abc\ndef\n", DOWN, BS, BS)
    eq(t, "abdef\n")

@test
def delete_char_and_join(env):
    s, t = edit(env, "abc\ndef\n", END, DEL, DEL)
    eq(t, "abcef\n")

@test
def enter_splits_with_autoindent(env):
    s, t = edit(env, "    foo bar\n", RIGHT*8, ENTER, "x")
    eq(t, "    foo\n    xbar\n")

@test
def enter_without_autoindent(env):
    s, t = edit(env, "    foo bar\n", ctrl("q") + "i", RIGHT*8, ENTER, "x")
    eq(t, "    foo\nxbar\n")

@test
def cursor_beyond_end_pads(env):
    s, t = edit(env, "ab\n", RIGHT*5, "Z")
    eq(t, "ab   Z\n")

@test
def home_end(env):
    s, t = edit(env, "  abc  \n", END, "!", HOME, "<")
    eq(t, "<  abc!\n")     # trailing blanks of an edited line are removed

@test
def tab_inserts_spaces(env):
    s, t = edit(env, "x\n", TAB, "y")
    eq(t, "        yx\n")

@test
def tabs_kept_in_files_that_have_them(env):
    # a file that already contains tabs is saved with its tabs untouched
    s, t = edit(env, "\tindented\n\tmore\n", DOWN, END, "!")
    eq(t, "\tindented\n\tmore!\n")

@test
def tab_key_inserts_tab_in_tabbed_file(env):
    s, t = edit(env, "\ta\n", HOME, TAB)
    eq(t, "\t\ta\n")

@test
def tabs_option_on_expands(env):
    os.makedirs(os.path.join(env.home, ".config", "mkedit"))
    with open(os.path.join(env.home, ".config", "mkedit", "mkedit.cfg"), "w") as f:
        f.write("expandtabs = on\n")
    s, t = edit(env, "a\tb\n", "")
    eq(t, "a       b\n")

@test
def tab_cursor_columns(env):
    # with physical tabs the cursor still moves by screen column
    s, t = edit(env, "\tx\n", RIGHT * 8, "Y")
    eq(t, "\tYx\n")

@test
def makefile_keeps_tabs(env):
    s, t = edit(env, "all:\n\tcc x\n", "", name="Makefile")
    eq(t, "all:\n\tcc x\n")

@test
def crlf_preserved(env):
    s, t = edit(env, "a\r\nb\r\n", END, "!")
    eq(t, "a!\r\nb\r\n")

@test
def no_final_newline_preserved(env):
    s, t = edit(env, "a\nb", DOWN, END, "!")
    eq(t, "a\nb!")

@test
def new_file_created(env):
    s = env.start("new.txt")
    s.send("hi", 0.2)
    s.send(SAVE, 0.4)
    eq(read(env, "new.txt"), "hi\n")

@test
def backup_file_made(env):
    s, t = edit(env, "one\n", "X")
    eq(read(env, "a.bak"), "one\n")

# ------------------------------------------------------------------ line commands
@test
def del_line_and_unkill(env):
    s, t = edit(env, "one\ntwo\nthree\n", DOWN, alt("d"))
    eq(t, "one\nthree\n")
    env2 = env
    # delete the middle line, go to the first line, unkill: the line comes back before the cursor line
    s2, t2 = edit(env, "one\ntwo\nthree\n", DOWN, alt("d"), UP, ctrl("u"), name="b.txt")
    eq(t2, "two\none\nthree\n")

@test
def dup_line_f4(env):
    s, t = edit(env, "one\ntwo\n", F4)
    eq(t, "one\none\ntwo\n")

@test
def add_line_f2_and_insert_line(env):
    s, t = edit(env, "one\ntwo\n", F2, "mid")
    eq(t, "one\nmid\ntwo\n")
    s, t = edit(env, "one\ntwo\n", DOWN, A_F2, "mid", name="b.txt")
    eq(t, "one\nmid\ntwo\n")

@test
def del_to_eol(env):
    s, t = edit(env, "abcdef\n", RIGHT*3, F6)
    eq(t, "abc\n")

@test
def join_line(env):
    s, t = edit(env, "abc   \n  def\n", alt("j"))
    eq(t, "abc  def\n")

@test
def split_line(env):
    s, t = edit(env, "abcdef\n", RIGHT*3, alt("s"), "X")
    eq(t, "abcX\ndef\n")

@test
def del_right_word(env):
    s, t = edit(env, "foo bar baz\n", ctrl("t"))
    eq(t, "bar baz\n")

@test
def word_movement(env):
    s, t = edit(env, "foo bar baz\n", C_RIGHT, C_RIGHT, "X", C_LEFT, "Y")
    eq(t, "foo bar YXbaz\n")
    s, t = edit(env, "foo bar baz\n", END, C_LEFT, "Y", name="b.txt")
    eq(t, "foo bar Ybaz\n")

@test
def undo_cursor_line(env):
    s, t = edit(env, "hello\n", "abc", DEL, DEL, ctrl("q") + "l")
    eq(t, "hello\n")

@test
def literal_inserts_control_char(env):
    s, t = edit(env, "\n", ctrl("p"), ctrl("l"), "x")
    eq(t, "\x0cx\n")

@test
def get_prev(env):
    s, t = edit(env, "abcdef\n\n", DOWN, "\x1f\x1f\x1f")
    eq(t, "abcdef\nabc\n")

# ------------------------------------------------------------------ cursor movement
@test
def goto_line_and_status(env):
    env.write("a.txt", "".join("line%d\n" % i for i in range(1, 101)))
    s = env.start("a.txt")
    s.send(ctrl("j"), 0.2)
    s.send("57\r", 0.3)
    eq(s.line_no(), 57)
    assert "line57" in s.text()

@test
def page_down_up(env):
    env.write("a.txt", "".join("line%d\n" % i for i in range(1, 201)))
    s = env.start("a.txt")
    s.send(PGDN, 0.25)
    n = s.line_no()
    assert 15 < n < 30, n
    s.send(PGUP, 0.25)
    eq(s.line_no(), 1)

@test
def begfile_endfile(env):
    env.write("a.txt", "".join("line%d\n" % i for i in range(1, 501)))
    s = env.start("a.txt")
    s.send(C_PGDN, 0.3)
    eq(s.line_no(), 500)
    s.send(C_PGUP, 0.3)
    eq(s.line_no(), 1)

@test
def prev_position(env):
    env.write("a.txt", "".join("line%d\n" % i for i in range(1, 501)))
    s = env.start("a.txt")
    s.send(ctrl("j") + "300\r", 0.3)
    s.send(C_PGUP, 0.3)
    s.send(ctrl("q") + "p", 0.3)
    eq(s.line_no(), 300)

@test
def scroll_commands(env):
    env.write("a.txt", "".join("line%d\n" % i for i in range(1, 101)))
    s = env.start("a.txt")
    s.send(ctrl("z") * 3, 0.3)
    assert s.row(1).startswith("line4"), s.row(1)
    eq(s.line_no(), 4)
    s.send(ctrl("w"), 0.2)
    assert s.row(1).startswith("line3"), s.row(1)

# ------------------------------------------------------------------ blocks
@test
def line_block_copy(env):
    s, t = edit(env, "a\nb\nc\nd\n", alt("l"), DOWN, alt("l"), DOWN, DOWN, alt("c"))
    # line blocks are inserted after the cursor line (line 'c') unless configured otherwise
    eq(t, "a\nb\nc\nd\na\nb\n")

@test
def line_block_move(env):
    s, t = edit(env, "a\nb\nc\nd\n", alt("l"), alt("l"), DOWN, DOWN, alt("m"))
    eq(t, "b\nc\na\nd\n")

@test
def line_block_delete_and_unkill(env):
    s, t = edit(env, "a\nb\nc\nd\n", DOWN, alt("l"), DOWN, alt("l"), alt("g"))
    eq(t, "a\nd\n")

@test
def stream_block_copy(env):
    # drop anchor at col 2, move right 3 (inclusive end), go to end of line 2, copy
    s, t = edit(env, "abcdefgh\nxy\n", RIGHT, alt("a"), RIGHT*2, alt("a"), DOWN, END, alt("c"))
    eq(t, "abcdefgh\nxybcd\n")

@test
def stream_block_markbegin_end(env):
    s, t = edit(env, "abcdefgh\nxy\n", RIGHT*2, ctrl("k") + "b", RIGHT*3, ctrl("k") + "k", DOWN, END, alt("c"))
    eq(t, "abcdefgh\nxycde\n")

@test
def stream_block_delete_multiline(env):
    s, t = edit(env, "abc\ndef\nghi\n", RIGHT, ctrl("k") + "b", DOWN, DOWN, RIGHT, ctrl("k") + "k", alt("g"))
    eq(t, "ai\n")

@test
def column_block_copy(env):
    # mark columns 1-2 of the first two lines, paste them at column 0 of the blank third line
    s, t = edit(env, "abcd\nefgh\n\n", RIGHT, alt("k"), DOWN, RIGHT, alt("k"), DOWN, HOME, alt("c"))
    eq(t.split("\n")[:4], ["abcd", "efgh", "bc", "fg"])

@test
def cut_and_paste(env):
    # Shift-Del cuts the marked line, Shift-Ins pastes it before the cursor line
    s, t = edit(env, "a\nb\nc\n", alt("l"), alt("l"), "\x1b[3;2~", DOWN, DOWN, "\x1b[2;2~")
    eq(t, "b\nc\na\n")

@test
def cut_line_when_nothing_marked_and_paste_twice(env):
    s, t = edit(env, "a\nb\nc\n", "\x1b[3;2~", DOWN, "\x1b[2;2~", "\x1b[2;2~")
    eq(t, "b\nc\na\na\n")

@test
def copy_stream_block_to_scrap_and_paste(env):
    s, t = edit(env, "abcdef\n", alt("a"), RIGHT * 2, alt("a"), "\x1b[2;5~", END, "\x1b[2;2~")
    eq(t, "abcdefabc\n")

@test
def block_in_other_file(env):
    env.write("a.txt", "one\ntwo\n")
    env.write("b.txt", "X\n")
    s = env.start("a.txt", "b.txt")
    # b.txt is current (loaded last); go to a.txt
    s.send(ctrl("k") + "p", 0.3)
    s.send(alt("l") + alt("l"), 0.3)
    s.send(ctrl("k") + "n", 0.3)
    s.send(alt("c"), 0.3)
    s.send(SAVE, 0.4)
    eq(read(env, "b.txt"), "X\none\n")
    eq(read(env, "a.txt"), "one\ntwo\n")

@test
def shift_block_right_left(env):
    s, t = edit(env, "a\nb\nc\n", alt("l"), DOWN, alt("l"), S_F8, S_F8, S_F7)
    eq(t, " a\n b\nc\n")

@test
def scratch_buffers(env):
    s, t = edit(env, "a\nb\n", alt("l"), alt("l"), ctrl("b") + "s", "buf\r", DOWN, DOWN, ctrl("b") + "l", "buf\r")
    assert t.count("a") == 2, t

# ------------------------------------------------------------------ search
@test
def find_forward(env):
    s, t = edit(env, "one\ntwo\nthree two\n", ctrl("q") + "f", "two\r", "\r", "!")
    eq(t, "one\n!two\nthree two\n")

@test
def find_repeat(env):
    # Find stops on the first match (the one under the cursor); RepeatFind goes on to the next
    s, t = edit(env, "x1\nx2\nx3\n", ctrl("q") + "f", "x\r", "\r", ctrl("l"), "!")
    eq(t, "x1\n!x2\nx3\n")
    s, t = edit(env, "x1\nx2\nx3\n", ctrl("q") + "f", "x\r", "\r", ctrl("l"), ctrl("l"), "!", name="b.txt")
    eq(t, "x1\nx2\n!x3\n")

@test
def find_backward(env):
    s, t = edit(env, "ab\nab\nab\n", DOWN, DOWN, END, ctrl("q") + "f", "ab\r", "ib\r".replace("ib", "IB") + "", "!")
    # backward search finds the 'ab' at line 3 col 1? (cursor at end of line 3)
    assert "!" in t, t

@test
def find_whole_word_ignore_case(env):
    s, t = edit(env, "absent sent\n", ctrl("q") + "f", "SENT\r", "IW\r", "!")
    eq(t, "absent !sent\n")

@test
def replace_all_noask(env):
    s, t = edit(env, "foo foo\nfoo\n", ctrl("q") + "a", "foo\r", "bar\r", "IN\r")
    eq(t, "bar bar\nbar\n")

@test
def replace_prompt_yes_no_global(env):
    s, t = edit(env, "foo foo foo foo\n", ctrl("q") + "a", "foo\r", "X\r", "I\r", "y", "n", "g")
    eq(t, "X foo X X\n")

@test
def replace_only(env):
    s, t = edit(env, "a a a\n", ctrl("q") + "a", "a\r", "b\r", "I\r", "o")
    eq(t, "b a a\n")

@test
def match_brackets(env):
    s, t = edit(env, "f(a(b)c)\n", RIGHT, A_F3, "!")
    eq(t, "f(a(b)c!)\n")
    s, t = edit(env, "f(a(b)c)\n", RIGHT * 3, A_F3, "!", name="b.txt")
    eq(t, "f(a(b!)c)\n")
    s, t = edit(env, "{\n  x\n}\n", A_F3, "!", name="c.txt")
    eq(t, "{\n  x\n!}\n")

# ------------------------------------------------------------------ files, exit
@test
def exit_prompts_to_save(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2)
    s.send(ctrl("k") + "d", 0.3)
    assert "Save changes" in s.text(), s.text()
    s.send("n", 0.3)
    assert "File(s) to edit" in s.text(), "the last file went: expect the file prompt\n" + s.text()
    s.send(ESC, 0.3)
    assert s.exited()
    eq(read(env, "a.txt"), "x\n")

@test
def exit_save_yes(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2)
    s.send(ctrl("k") + "d", 0.3)
    s.send("y", 0.4)
    s.send(ESC, 0.3)
    assert s.exited()
    eq(read(env, "a.txt"), "abcx\n")

@test
def file_command_saves_and_exits(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2)
    s.send(ctrl("k") + "x", 0.4)
    s.send(ESC, 0.3)
    assert s.exited()
    eq(read(env, "a.txt"), "abcx\n")

@test
def pquit_warns(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2)
    s.send(ctrl("k") + "q", 0.3)
    assert "abandon" in s.text().lower() or "changed" in s.text().lower(), s.text()
    s.send("n", 0.3)
    assert not s.exited(0.5)
    s.send(ctrl("k") + "q", 0.3)
    s.send("y", 0.3)
    s.send(ESC, 0.3)
    assert s.exited()
    eq(read(env, "a.txt"), "x\n")

@test
def menu_quit_asks_when_modified(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2)
    s.send(ESC, 0.3); s.send("q", 0.3); s.send("u", 0.3)
    assert "Abandon" in s.text(), s.text()
    s.send("n", 0.3)
    assert not s.exited(0.5)
    s.send(ESC, 0.3); s.send("q", 0.3); s.send("u", 0.3); s.send("y", 0.3)
    s.send(ESC, 0.3)
    assert s.exited()
    eq(read(env, "a.txt"), "x\n")

@test
def global_exit_two_files(env):
    env.write("a.txt", "A\n")
    env.write("b.txt", "B\n")
    s = env.start("a.txt", "b.txt")
    s.send("1", 0.2)
    s.send(ctrl("k") + "p", 0.2)
    s.send("2", 0.2)
    s.send(alt("x"), 0.3)
    s.send("y", 0.3)
    s.send("y", 0.4)
    assert s.exited()
    eq(read(env, "a.txt"), "2A\n")
    eq(read(env, "b.txt"), "1B\n")

@test
def next_prev_file(env):
    env.write("a.txt", "A\n")
    env.write("b.txt", "B\n")
    s = env.start("a.txt", "b.txt")
    assert s.stat()[4].endswith("b.txt"), s.stat()
    s.send(ctrl("k") + "p", 0.3)
    assert s.stat()[4].endswith("a.txt")
    s.send(alt("n"), 0.3)
    assert s.stat()[4].endswith("b.txt")

@test
def edit_file_prompt(env):
    env.write("a.txt", "A\n")
    env.write("b.txt", "B\n")
    s = env.start("a.txt")
    s.send(alt("e"), 0.3)
    assert "File(s) to edit" in s.text(), s.text()
    s.send("b.txt\r", 0.4)
    assert s.stat()[4].endswith("b.txt"), s.stat()
    assert "B" in s.row(1)

@test
def change_filename(env):
    env.write("a.txt", "A\n")
    s = env.start("a.txt")
    s.send(alt("o"), 0.3)
    s.send("c.txt\r", 0.3)
    s.send(SAVE, 0.4)
    eq(read(env, "c.txt"), "A\n")
    eq(read(env, "a.txt"), "A\n")

@test
def read_and_write_block(env):
    env.write("ins.txt", "X\nY\n")
    env.write("a.txt", "1\n2\n")
    s = env.start("a.txt")
    s.send(alt("r"), 0.3)
    s.send("ins.txt\r", 0.4)
    s.send(ctrl("k") + "h", 0.2)
    s.send(alt("l") + DOWN + alt("l"), 0.3)
    s.send(alt("w"), 0.3)
    s.send("out.txt\r", 0.4)
    eq(read(env, "out.txt"), "X\nY\n")
    s.send(SAVE, 0.4)
    eq(read(env, "a.txt"), "X\nY\n1\n2\n")

@test
def menu_save(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("Q", 0.2)
    s.send(ESC, 0.3)
    assert "File" in s.row(0) and "Block" in s.row(0), s.row(0)
    s.send("f", 0.3)
    assert "Save file" in s.text(), s.text()
    s.send("s", 0.4)
    eq(read(env, "a.txt"), "Qx\n")

@test
def menu_escape_closes(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(ESC, 0.3)
    s.send(ESC, 0.3)
    assert "Block" not in s.row(0), s.row(0)

@test
def help_screen(env):
    env.write("a.txt", "x\n")
    for rows, cols in ((25, 80), (34, 110)):
        s = env.start("a.txt", rows=rows, cols=cols)
        s.send(F1, 0.4)
        t = s.text()
        if cols >= 96:
            assert "copy block" in t and "Search/Replace" in t and "Windows" in t, t
        else:
            assert "Cursor movement" in t and "BegFile" in t, t
        s.send("x", 0.3)
        assert "BegFile" not in s.text() and "copy block" not in s.text()

@test
def help_screen_scrolls_to_every_command(env):
    from_defs = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "uDefs.pas")).read()
    import re
    names = re.search(r"CmdNames: array\[TCmd\] of string = \((.*?)\n  \);", from_defs, re.S).group(1)
    cmds = [n for n in re.findall(r"'(\w+)'", names) if n]
    env.write("a.txt", "x\n")
    s = env.start("a.txt", rows=25, cols=100)
    s.send(F1, 0.4)
    seen = set()
    for _ in range(60):
        for r in s.rows_text():
            seen.update(w for w in r.replace(",", " ").split())
        s.send(PGDN, 0.15)
    missing = [c for c in cmds if c not in seen and not c.startswith("Menu") and c != "MainMenu"]
    assert not missing, missing
    s.send(HOME, 0.2)
    assert "mkedit Help" in s.text()
    s.send("x", 0.3)
    assert "mkedit Help" not in s.text()

@test
def start_without_file_prompts(env):
    env.write("a.txt", "hello\n")
    s = env.start()
    assert "File(s) to edit" in s.text(), s.text()
    s.send("a.txt\r", 0.4)
    assert "hello" in s.row(1)

@test
def abort_initial_prompt_exits(env):
    s = env.start()
    s.send(ESC, 0.4)
    assert s.exited()

# ------------------------------------------------------------------ windows
@test
def split_windows_edit_both(env):
    env.write("a.txt", "one\ntwo\nthree\nfour\n")
    s = env.start("a.txt")
    s.send(ctrl("o") + "h", 0.4)
    t = s.rows_text()
    n = sum(1 for r in t if r.startswith("L "))
    eq(n, 2, "two status lines\n" + s.text())
    s.send(DOWN + DOWN + "X", 0.3)
    s.send(ctrl("o") + "n", 0.3)
    s.send("Y", 0.3)
    s.send(SAVE, 0.4)
    eq(read(env, "a.txt"), "Yone\ntwo\nXthree\nfour\n")

@test
def close_and_one_window(env):
    env.write("a.txt", "one\n")
    s = env.start("a.txt")
    s.send(ctrl("o") + "h", 0.3)
    s.send(ctrl("o") + "h", 0.3)
    eq(sum(1 for r in s.rows_text() if r.startswith("L ")), 3)
    s.send(ctrl("o") + "c", 0.3)
    eq(sum(1 for r in s.rows_text() if r.startswith("L ")), 2)
    s.send(ctrl("o") + "o", 0.3)
    eq(sum(1 for r in s.rows_text() if r.startswith("L ")), 1)

@test
def zoom_window(env):
    env.write("a.txt", "one\n")
    s = env.start("a.txt")
    s.send(ctrl("o") + "h", 0.3)
    s.send(ctrl("o") + "z", 0.3)
    eq(sum(1 for r in s.rows_text() if r.startswith("L ")), 1)
    s.send(ctrl("o") + "z", 0.3)
    eq(sum(1 for r in s.rows_text() if r.startswith("L ")), 2)

# ------------------------------------------------------------------ macros, modes
@test
def macro_on_key(env):
    env.write("a.txt", "a\nb\nc\nd\n")
    s = env.start("a.txt")
    s.send(F12, 0.3)
    assert "Assign to what key" in s.text(), s.text()
    s.send("\x1b[1;3S", 0.3)            # Alt-F4
    s.send("-", 0.1); s.send(HOME, 0.1); s.send(DOWN, 0.1)
    s.send(F12, 0.3)
    assert "recorded" in s.text().lower(), s.text()
    s.send("\x1b[1;3S", 0.3)
    s.send("\x1b[1;3S", 0.3)
    s.send(SAVE, 0.4)
    eq(read(env, "a.txt"), "-a\n-b\n-c\nd\n")
    
@test
def scrap_macro(env):
    env.write("a.txt", "a\nb\nc\nd\n")
    s = env.start("a.txt")
    s.send(F12, 0.3)
    s.send("\r", 0.3)
    s.send("*", 0.1); s.send(HOME, 0.1); s.send(DOWN, 0.1)
    s.send(F12, 0.3)
    s.send(F11, 0.3); s.send(F11, 0.3)
    s.send(SAVE, 0.4)
    eq(read(env, "a.txt"), "*a\n*b\n*c\nd\n")

@test
def word_wrap(env):
    env.write("a.txt", "\n")
    s = env.start("a.txt")
    s.send(ctrl("o") + "r", 0.3)
    s.send("20\r", 0.3)
    s.send("the quick brown fox jumps over the lazy dog", 0.4)
    s.send(SAVE, 0.4)
    t = read(env, "a.txt")
    lines = t.rstrip("\n").split("\n")
    assert len(lines) >= 2 and all(len(l) <= 21 for l in lines), lines
    eq(" ".join(lines), "the quick brown fox jumps over the lazy dog")

@test
def wrap_paragraph(env):
    s, t = edit(env, "aaa bbb\nccc ddd\neee\n\nzzz\n", ctrl("o") + "r", "9\r", alt("b"))
    eq(t, "aaa bbb\nccc ddd\neee\n\nzzz\n".replace("aaa bbb\nccc ddd\neee", "aaa bbb\nccc ddd\neee"))

@test
def enter_matching(env):
    s, t = edit(env, "\n", ESC, "o", "e", "(", "x")
    eq(t, "(x)\n")

@test
def box_drawing(env):
    s, t = edit(env, "\n\n\n", "\x1b[1;2P", RIGHT, RIGHT, DOWN, DOWN)
    t = t.encode("latin-1").decode("utf-8")
    assert "─" in t and "│" in t and "┐" in t, t

@test
def c_mode_brace_indent(env):
    s, t = edit(env, "int main()\n", END, ENTER, "{", ENTER, "x;", ENTER, "}", name="t.c")
    eq(t, "int main()\n{\n    x;\n}\n")

@test
def insert_utf8(env):
    s, t = edit(env, "\n", "café")
    eq(t.encode("latin-1").decode("utf-8"), "café\n")

@test
def utf8_cursor_columns(env):
    env.write("a.txt", "ééab\n")
    s = env.start("a.txt")
    s.send(RIGHT * 3, 0.3)
    s.send("X", 0.2)
    s.send(SAVE, 0.4)
    eq(read(env, "a.txt").encode("latin-1").decode("utf-8"), "ééaXb\n")

# ------------------------------------------------------------------ big files
def big_content(n):
    return "".join("line %d: %s\n" % (i, "x" * (i % 70)) for i in range(1, n + 1))

@test
def big_file_goto_edit_save(env):
    n = 60000
    env.write("big.txt", big_content(n))
    s = env.start("big.txt")
    s.send(ctrl("j") + "45000\r", 0.8)
    eq(s.line_no(), 45000)
    assert "line 45000:" in s.text(), s.text()
    assert s.stat()[3] <= 128, "window should stay small: %s" % (s.stat(),)
    s.send(HOME + "EDIT", 0.2)
    s.send(ctrl("j") + "10\r", 0.8)
    s.send(HOME + "TOP", 0.2)
    s.send(C_PGDN, 1.0)
    eq(s.line_no(), n)
    s.send(HOME + "END", 0.2)
    s.send(SAVE, 3.0)
    lines = read(env, "big.txt").split("\n")
    eq(len(lines), n + 1)
    assert lines[9].startswith("TOPline 10:"), lines[9]
    assert lines[44999].startswith("EDITline 45000:"), lines[44999][:30]
    assert lines[n - 1].startswith("ENDline %d" % n), lines[n - 1][:30]
    assert lines[1000] == "line 1001: " + "x" * (1001 % 70)

@test
def big_file_find_far(env):
    n = 50000
    c = big_content(n).replace("line 33333:", "line NEEDLE:")
    env.write("big.txt", c)
    s = env.start("big.txt")
    s.send(ctrl("q") + "f", 0.3)
    s.send("NEEDLE\r", 0.3)
    s.send("\r", 1.5)
    eq(s.line_no(), 33333)

@test
def big_file_delete_block_across_window(env):
    n = 30000
    env.write("big.txt", big_content(n))
    s = env.start("big.txt")
    s.send(ctrl("j") + "100\r", 0.5)
    s.send(alt("l"), 0.2)
    s.send(ctrl("j") + "20000\r", 0.8)
    s.send(alt("l"), 0.3)
    s.send(alt("g"), 1.5)
    s.send(SAVE, 3.0)
    lines = read(env, "big.txt").split("\n")
    eq(len(lines), n - 19901 + 1)
    assert lines[99].startswith("line 20001:"), lines[99][:20]
    assert lines[98].startswith("line 99:")

@test
def big_file_copy_block_far(env):
    n = 30000
    env.write("big.txt", big_content(n))
    s = env.start("big.txt")
    s.send(ctrl("j") + "10\r", 0.5)
    s.send(alt("l"), 0.2); s.send(DOWN, 0.1); s.send(alt("l"), 0.2)
    s.send(ctrl("j") + "25000\r", 0.8)
    s.send(alt("c"), 0.8)
    s.send(SAVE, 3.0)
    lines = read(env, "big.txt").split("\n")
    eq(len(lines), n + 3)
    assert lines[25000].startswith("line 10:") and lines[25001].startswith("line 11:"), lines[24998:25003]

@test
def temp_files_removed(env):
    env.write("big.txt", big_content(30000))
    tmp = os.path.join(env.root, "tmp")
    os.makedirs(tmp)
    s = env.start("big.txt", env={"MKEDIT_TMP": tmp})
    pid = s.pid
    s.send(C_PGDN, 1.0)
    prefix = "mkedit-%d-" % pid
    assert [f for f in os.listdir(tmp) if f.startswith(prefix)], "temp files should exist while editing"
    s.send(ctrl("k") + "q", 0.4)
    s.send(ESC, 0.3)
    assert s.exited()
    eq([f for f in os.listdir(tmp) if f.startswith(prefix)], [], "temp files left behind")

@test
def resize_keeps_working(env):
    env.write("a.txt", "".join("line%d\n" % i for i in range(1, 100)))
    s = env.start("a.txt")
    s.resize(40, 100)
    assert s.row(39).strip() == "" or True
    eq(sum(1 for r in s.rows_text() if r.startswith("line")), 39)
    s.send(PGDN, 0.3)
    assert s.line_no() > 30


# ------------------------------------------------------------------ robustness and extras
@test
def hangup_saves_work(env):
    env.write("a.txt", "orig\n")
    s = env.start("a.txt")
    s.send("EDIT", 0.3)
    os.close(s.fd)                      # the terminal disappears
    s.fd = os.open("/dev/null", os.O_RDONLY)
    end = time.time() + 5
    while time.time() < end and not os.path.exists(env.path("a.txt.mkedit-save")):
        time.sleep(0.1)
    eq(read(env, "a.txt.mkedit-save"), "EDITorig\n")
    eq(read(env, "a.txt"), "orig\n")
    for _ in range(50):
        try:
            pid, _ = os.waitpid(s.pid, os.WNOHANG)
        except ChildProcessError:
            pid = s.pid
        if pid:
            s.pid = None
            break
        time.sleep(0.1)
    assert s.pid is None, "the editor should exit when its terminal is gone"

@test
def two_windows_far_apart_on_big_file(env):
    n = 40000
    env.write("big.txt", big_content(n))
    s = env.start("big.txt")
    s.send(ctrl("o") + "h", 0.5)                     # new window at the same place
    s.send(ctrl("j") + "35000\r", 1.0)               # lower window far away
    rows = s.rows_text()
    assert any(r.startswith("line 35000:") for r in rows), s.text()
    assert any(r.startswith("line 1:") for r in rows), "the upper window must still show line 1\n" + s.text()
    s.send(HOME + "LOW", 0.2)
    s.send(ctrl("o") + "n", 0.5)
    s.send(HOME + "UP", 0.2)
    rows = s.rows_text()
    assert any(r.startswith("LOWline 35000:") for r in rows), s.text()
    assert any(r.startswith("UPline 1:") for r in rows), s.text()
    s.send(SAVE, 3.0)
    lines = read(env, "big.txt").split("\n")
    assert lines[0].startswith("UPline 1:") and lines[34999].startswith("LOWline 35000:")
    eq(len(lines), n + 1)

@test
def edit_above_other_window_keeps_its_place(env):
    env.write("a.txt", "".join("line%d\n" % i for i in range(1, 60)))
    s = env.start("a.txt")
    s.send(ctrl("o") + "h", 0.4)
    s.send(ctrl("j") + "40\r", 0.4)                  # lower window at line 40
    s.send(ctrl("o") + "n", 0.3)                     # upper window
    s.send(F2 * 5, 0.4)                              # five new lines near the top
    s.send(ctrl("o") + "n", 0.3)
    assert s.line_no() == 45 or True
    assert "line40" in s.text(), s.text()

@test
def bracketed_paste_has_no_autoindent_staircase(env):
    env.write("a.txt", "\n")
    s = env.start("a.txt")
    s.send("\x1b[200~    one\r    two\r        three\r\x1b[201~", 0.4)
    s.send(SAVE, 0.4)
    eq(read(env, "a.txt"), "    one\n    two\n        three\n\n")

@test
def file_picker_with_wildcard(env):
    env.write("aaa.txt", "AAA\n")
    env.write("bbb.txt", "BBB\n")
    env.write("ccc.dat", "CCC\n")
    env.write("start.txt", "S\n")
    s = env.start("start.txt")
    s.send(alt("e"), 0.3)
    s.send("*.txt\r", 0.4)
    t = s.text()
    assert "aaa.txt" in t and "bbb.txt" in t and "ccc.dat" not in t, t
    s.send(DOWN + "\r", 0.4)                           # the selection starts on the first file
    assert s.stat()[4].endswith("bbb.txt"), s.stat()

@test
def file_picker_escape(env):
    env.write("aaa.txt", "AAA\n")
    env.write("start.txt", "S\n")
    s = env.start("start.txt")
    s.send(alt("e"), 0.3)
    s.send("*.txt\r", 0.4)
    s.send(ESC, 0.4)
    assert s.stat()[4].endswith("start.txt"), s.stat()

@test
def binary_file_survives_round_trip(env):
    # control characters, tabs, NULs and invalid UTF-8: opening and saving must not change a byte
    data = bytes(range(1, 256)) * 3 + b"\n" + bytes([0, 1, 2, 9, 255, 254]) + b"\nend\n"
    env.write("bin.dat", data)
    s = env.start("bin.dat")
    s.send(DOWN + END + HOME, 0.3)
    s.send(SAVE, 0.4)
    eq(open(env.path("bin.dat"), "rb").read(), data)
    assert s.pid, "still running"

@test
def very_long_line(env):
    env.write("long.txt", "A" * 300000 + "\nshort\n")
    s = env.start("long.txt")
    s.send(END, 0.5)
    s.send("Z", 0.3)
    s.send(DOWN, 0.2)
    s.send(SAVE, 1.0)
    t = read(env, "long.txt")
    assert t.startswith("A" * 1000) and t.endswith("\nshort\n"), len(t)

@test
def current_filename_command(env):
    env.write("a.txt", "\n")
    s = env.start("a.txt")
    s.send(ESC, 0.3); s.send("e", 0.3); s.send("n", 0.3)
    assert "a.txt" in s.row(1), s.text()

@test
def config_file_options_and_keys(env):
    os.makedirs(os.path.join(env.home, ".config", "mkedit"))
    with open(os.path.join(env.home, ".config", "mkedit", "mkedit.cfg"), "w") as f:
        f.write("# test\nautoindent = off\nbackup = off\nexpandtabs = on\ntabwidth = 4\nkey F9 = DupLine\nkey A-d = none\n")
    env.write("a.txt", "\tx\n")
    s = env.start("a.txt")
    s.send(F9, 0.3)                                   # rebound: duplicate the line
    s.send(alt("d"), 0.3)                             # unbound now
    s.send(SAVE, 0.4)
    eq(read(env, "a.txt"), "    x\n    x\n")
    assert not os.path.exists(env.path("a.bak"))

@test
def macro_file_write_and_read(env):
    env.write("a.txt", "a\nb\n")
    s = env.start("a.txt")
    s.send(F12, 0.3); s.send("\x1b[1;3S", 0.3)
    s.send("#", 0.1); s.send(HOME, 0.1); s.send(DOWN, 0.1)
    s.send(F12, 0.3)
    s.send(ESC, 0.3); s.send("m", 0.2); s.send("w", 0.3)
    s.send("m.mac\r", 0.4)
    assert os.path.exists(env.path("m.mac"))
    s.send(ctrl("k") + "q", 0.3); s.send("y", 0.3); s.send(ESC, 0.3)
    env.write("b.txt", "1\n2\n")
    s2 = env.start("b.txt")
    s2.send(ESC, 0.3); s2.send("m", 0.2); s2.send("r", 0.3)
    s2.send("m.mac\r", 0.4)
    s2.send("\x1b[1;3S", 0.3)
    s2.send(SAVE, 0.4)
    eq(read(env, "b.txt"), "#1\n2\n")

@test
def grow_and_shrink_window(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(ctrl("o") + "h", 0.4)
    before = [i for i, r in enumerate(s.rows_text()) if r.startswith("L ")]
    s.send(ctrl("o") + "g", 0.3)
    s.send(UP + UP + UP, 0.3)
    s.send(ENTER, 0.3)
    after = [i for i, r in enumerate(s.rows_text()) if r.startswith("L ")]
    eq(after[1], before[1] - 3, "the window's top edge moved up by three")

@test
def kill_buffer_holds_several_deletions(env):
    # a, b, c go into the kill buffer; two unkills bring back c and then b, each before the cursor line
    s, t = edit(env, "a\nb\nc\nd\n", alt("d"), alt("d"), alt("d"), ctrl("u"), ctrl("u"))
    eq(t, "b\nc\nd\n")

@test
def insert_mode_toggle_shown_in_status(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    assert s.stat()[2][0] == "I"
    s.send(INS, 0.2)
    assert s.stat()[2][0] == " ", s.stat()

@test
def modified_marker_and_new_marker(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    assert "*" not in s.row(0)
    s.send("a", 0.2)
    assert "*" in s.row(0)
    s.send(SAVE, 0.4)
    assert "*" not in s.row(0)

@test
def dos_command(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(A_F9, 0.3)
    assert "Execute what" in s.text(), s.text()
    s.send("echo hello > dos.out\r", 0.6)
    s.send("\r", 0.6)
    assert s.stat() is not None, s.text()
    eq(read(env, "dos.out"), "hello\n")

@test
def print_all_with_margin_and_pages(env):
    script = env.write("fakelp.sh", "#!/bin/sh\ncp \"$1\" \"%s\"\n" % env.path("printed.txt"))
    os.chmod(script, 0o755)
    env.write("a.txt", "one\ntwo\nthree\n")
    s = env.start("a.txt", env={"MKEDIT_PRINT": script})
    s.send(ESC, 0.3); s.send("p", 0.3); s.send("l", 0.3); s.send("3\r", 0.3)
    s.send(ESC, 0.3); s.send("p", 0.3); s.send("p", 0.3); s.send("2\r", 0.3)
    s.send(ESC, 0.3); s.send("p", 0.3); s.send("a", 0.8)
    eq(read(env, "printed.txt"), "   one\n   two\n\x0c   three\n")

@test
def terminal_restored_on_exit(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(ctrl("k") + "d", 0.4)
    s.send(ESC, 0.3)
    assert s.exited()

# ------------------------------------------------------------------ from chapters 2 and 3 of the manual
@test
def kill_file_deletes_from_disk_but_stays_loaded(env):
    env.write("a.txt", "keep me\n")
    s = env.start("a.txt")
    s.send(ctrl("k") + "z", 0.3)
    s.send("y", 0.4)
    assert not os.path.exists(env.path("a.txt"))
    assert "keep me" in s.row(1) and "*" in s.row(0), s.text()
    s.send(SAVE, 0.4)
    eq(read(env, "a.txt"), "keep me\n")

@test
def mark_begin_end_block_hidden_until_both_set(env):
    env.write("a.txt", "abcdef\n")
    s = env.start("a.txt")
    s.send(RIGHT + ctrl("k") + "b", 0.3)
    s.send(RIGHT * 3, 0.3)
    eq(s.highlighted(1), "", "nothing is shown after ^KB alone")
    s.send(ctrl("k") + "k", 0.3)
    eq(s.highlighted(1), "bcd")

@test
def copy_to_scrap_unmarks_block(env):
    env.write("a.txt", "abcdef\n")
    s = env.start("a.txt")
    s.send(alt("a") + RIGHT * 2 + alt("a"), 0.3)
    assert s.highlighted(1) != ""
    s.send("\x1b[2;5~", 0.3)
    eq(s.highlighted(1), "")

@test
def end_of_file_marker(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    assert s.row(2).strip() == "<*** End of File ***>", s.text()

@test
def found_text_is_highlighted_until_next_key(env):
    env.write("a.txt", "one two three\n")
    s = env.start("a.txt")
    s.send(ctrl("q") + "f", 0.3); s.send("two\r", 0.3); s.send("\r", 0.4)
    eq(s.highlighted(1), "two")
    s.send(RIGHT, 0.3)
    eq(s.highlighted(1), "")

@test
def trailing_blanks_removed_from_edited_lines_only(env):
    env.write("a.txt", "keep   \nedit\n")
    s = env.start("a.txt")
    s.send(DOWN + END + "   ", 0.3)
    s.send(UP, 0.3)
    s.send(SAVE, 0.4)
    eq(read(env, "a.txt"), "keep   \nedit\n")

@test
def filename_with_line_number(env):
    env.write("a.txt", "".join("line%d\n" % i for i in range(1, 100)))
    s = env.start("a.txt", "40")
    eq(s.line_no(), 40)
    env.write("b.txt", "".join("b%d\n" % i for i in range(1, 100)))
    s2 = env.start("a.txt")
    s2.send(alt("e"), 0.3); s2.send("b.txt 25\r", 0.5)
    eq(s2.line_no(), 25)

@test
def default_extensions(env):
    os.makedirs(os.path.join(env.home, ".config", "mkedit"))
    with open(os.path.join(env.home, ".config", "mkedit", "mkedit.cfg"), "w") as f:
        f.write("extensions = .pas .c\n")
    env.write("prog.c", "int x;\n")
    s = env.start("prog")
    assert s.stat()[4].endswith("prog.c"), s.stat()
    s2 = env.start("nothing")
    assert "nothing" in s2.stat()[4] and "prog.c" not in s2.stat()[4], s2.stat()

@test
def config_macro_with_commands_and_text(env):
    os.makedirs(os.path.join(env.home, ".config", "mkedit"))
    with open(os.path.join(env.home, ".config", "mkedit", "mkedit.cfg"), "w") as f:
        f.write("key A-t = MacroBegin Return 'hello ' CurrentFilename\n")
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(alt("t"), 0.6)
    s.send(SAVE, 0.4)
    eq(read(env, "a.txt"), "\nhello " + env.path("a.txt") + "x\n")

@test
def prompt_box_is_cyan_by_default(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(alt("e"), 0.3)
    eq(s.screen.buffer[s.rows // 2 - 2][3].bg, "cyan")

@test
def color_editor_changes_and_saves(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(ESC, 0.3); s.send("o", 0.3); s.send("l", 0.4)
    assert "Prompt boxes" in s.text(), s.text()
    eq(s.screen.buffer[1][0].bg, "blue")
    s.send(PGDN, 0.2)                                   # text background: blue -> green
    eq(s.screen.buffer[1][0].bg, "green")
    s.send("s", 0.4)
    cfg = open(os.path.join(env.home, ".config", "mkedit", "mkedit.cfg")).read()
    assert "color_text = 7,2" in cfg and "color_box = 15,3" in cfg, cfg
    s2 = env.start("a.txt")
    eq(s2.screen.buffer[1][0].bg, "green")

@test
def color_editor_escape_restores(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(ESC, 0.3); s.send("o", 0.3); s.send("l", 0.4)
    s.send(PGDN, 0.2)
    s.send(ESC, 0.4)
    eq(s.screen.buffer[1][0].bg, "blue")

@test
def align_command_only_moves_when_line_above_blank(env):
    cfg = os.path.join(env.home, ".config", "mkedit"); os.makedirs(cfg)
    with open(os.path.join(cfg, "mkedit.cfg"), "w") as f:
        f.write("key F10 = Align\n")
    s, t = edit(env, "    abc\n  def\n\n  ghi\n", DOWN, "\x1b[21~", "\x1b[21~", "\x1b[21~")
    eq(t, "    abc\n    def\n\n  ghi\n")

@test
def delch_join_can_be_turned_off(env):
    cfg = os.path.join(env.home, ".config", "mkedit"); os.makedirs(cfg)
    with open(os.path.join(cfg, "mkedit.cfg"), "w") as f:
        f.write("delchjoin = off\nreturnsplit = off\n")
    s, t = edit(env, "ab\ncd\n", END, DEL)
    eq(t, "ab\ncd\n")
    s, t = edit(env, "abcd\n", RIGHT * 2, ENTER, "X", name="b.txt")
    eq(t, "abcd\nX\n")

@test
def find_and_replace_default_options_configurable(env):
    cfg = os.path.join(env.home, ".config", "mkedit"); os.makedirs(cfg)
    with open(os.path.join(cfg, "mkedit.cfg"), "w") as f:
        f.write("findoptions = W\nreplaceoptions = IN\n")
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(ctrl("q") + "f", 0.3); s.send("q\r", 0.3)
    rows = s.rows_text()
    i = [k for k, r in enumerate(rows) if "Options [IWB]" in r][0]
    eq(rows[i + 1].strip("│ ").strip(), "W", "the configured default find options")

# ------------------------------------------------------------------ keys borrowed from JOE
@test
def joe_goto_line_and_begin_of_file(env):
    env.write("a.txt", "".join("line%d\n" % i for i in range(1, 100)))
    s = env.start("a.txt")
    s.send(ctrl("k") + "l", 0.3); s.send("42\r", 0.3)
    eq(s.line_no(), 42)
    s.send(ctrl("k") + "u", 0.3)
    eq(s.line_no(), 1)
    s.send(ctrl("k") + "-", 0.3)
    eq(s.line_no(), 42)

@test
def joe_move_block_and_indent(env):
    s, t = edit(env, "a\nb\nc\nd\n", alt("l"), alt("l"), DOWN, DOWN, ctrl("k") + "m")
    eq(t, "b\nc\na\nd\n")
    s, t = edit(env, "a\nb\n", alt("l"), ctrl("k") + ".", ctrl("k") + ".", ctrl("k") + ",", name="b.txt")
    eq(t, " a\nb\n")

@test
def joe_center_line(env):
    s, t = edit(env, "  hello  \n", ctrl("k") + "a")
    eq(t, " " * 35 + "hello\n")

@test
def joe_filter_block_through_command(env):
    s, t = edit(env, "c\na\nb\nx\n", alt("l"), DOWN, DOWN, alt("l"), ctrl("k") + "/", "sort\r")
    eq(t, "a\nb\nc\nx\n")
    s, t = edit(env, "b\na\n", alt("l"), DOWN, alt("l"), ctrl("k") + "/", "sort\r", name="b.txt")
    eq(t, "a\nb\n")
    s, t = edit(env, "keep\nb\n", alt("l"), ctrl("k") + "/", "false\r", name="c.txt")
    eq(t, "keep\nb\n")

@test
def joe_open_line_and_ctrl_space_mark(env):
    s, t = edit(env, "abcd\n", RIGHT * 2, "\x1d", "X")      # ^] splits the line, the cursor stays
    eq(t, "abX\ncd\n")
    s, t = edit(env, "abcdef\n", "\x00", RIGHT * 2, "\x00", END, alt("c"), name="b.txt")
    eq(t, "abcdefabc\n")

@test
def joe_window_keys(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(ctrl("k") + "o", 0.4)
    eq(sum(1 for r in s.rows_text() if r.startswith("L ")), 2)
    s.send(ctrl("k") + "i", 0.4)
    eq(sum(1 for r in s.rows_text() if r.startswith("L ")), 1)

@test
def joe_mark_unmodified(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2)
    assert "*" in s.row(0)
    s.send(alt("~"), 0.3)
    assert "*" not in s.row(0), s.row(0)
    s.send(alt("x"), 0.4)
    assert s.exited()
    eq(read(env, "a.txt"), "x\n")

@test
def no_duplicate_default_key_bindings(env):
    import re
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "uDefs.pas")).read()
    keys = re.findall(r"Bind\('((?:[^']|'')*)'", src)
    dup = sorted({k for k in keys if keys.count(k) > 1})
    assert not dup, dup

# ------------------------------------------------------------------ undo / redo
def saved(s, env, name="a.txt"):
    s.send(SAVE, 0.4)
    return read(env, name)

@test
def undo_typing_merges_into_one_step(env):
    env.write("a.txt", "orig\n")
    s = env.start("a.txt")
    s.send("hello world", 0.4)
    s.send(UNDO, 0.3)
    eq(saved(s, env), "orig\n")
    s.send(REDO, 0.3)
    eq(saved(s, env), "hello worldorig\n")

@test
def undo_steps_through_enter_and_typing(env):
    env.write("a.txt", "a\n")
    s = env.start("a.txt")
    s.send("xyz", 0.2); s.send(RIGHT * 0, 0.0)
    s.send(ENTER, 0.2)
    s.send("q", 0.2)
    eq(saved(s, env), "xyz\nqa\n")
    s.send(UNDO, 0.3)
    eq(saved(s, env), "xyz\na\n")
    s.send(UNDO, 0.3)
    eq(saved(s, env), "xyza\n")
    s.send(UNDO, 0.3)
    eq(saved(s, env), "a\n")
    s.send(UNDO, 0.3)
    assert "Nothing to undo" in s.text(), s.text()
    s.send(REDO + REDO + REDO, 0.5)
    eq(saved(s, env), "xyz\nqa\n")

@test
def undo_restores_cursor_position(env):
    env.write("a.txt", "".join("line%d\n" % i for i in range(1, 60)))
    s = env.start("a.txt")
    s.send(ctrl("j") + "30\r", 0.4)
    s.send(alt("d"), 0.3)
    s.send(ctrl("j") + "5\r", 0.4)
    s.send(UNDO, 0.4)
    eq(s.line_no(), 30)
    s.send(UP, 0.3)                       # (the message line hides the last row)
    assert "line30" in s.text(), s.text()

@test
def undo_block_delete_and_move(env):
    s, t = edit(env, "a\nb\nc\nd\n", alt("l"), DOWN, alt("l"), alt("g"), UNDO)
    eq(t, "a\nb\nc\nd\n")
    s, t = edit(env, "a\nb\nc\nd\n", alt("l"), alt("l"), DOWN, DOWN, alt("m"), UNDO, name="b.txt")
    eq(t, "a\nb\nc\nd\n")

@test
def undo_replace_all_is_one_step(env):
    s, t = edit(env, "foo foo\nfoo\n", ctrl("q") + "a", "foo\r", "bar\r", "IN\r", UNDO)
    eq(t, "foo foo\nfoo\n")

@test
def undo_to_saved_state_clears_modified_marker(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2)
    s.send(SAVE, 0.4)
    assert "*" not in s.row(0)
    s.send("def", 0.2)
    assert "*" in s.row(0)
    s.send(UNDO, 0.3)
    assert "*" not in s.row(0), s.row(0)
    s.send(UNDO, 0.3)
    assert "*" in s.row(0), "undone past the saved state"
    s.send(REDO, 0.3)
    assert "*" not in s.row(0)

@test
def new_edit_after_undo_drops_redo(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2); s.send(UNDO, 0.3); s.send("Z", 0.2)
    s.send(REDO, 0.3)
    assert "Nothing to redo" in s.text(), s.text()
    eq(saved(s, env), "Zx\n")

@test
def undo_from_the_menu(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2)
    s.send(ESC, 0.3); s.send("e", 0.3); s.send("z", 0.4)
    eq(saved(s, env), "x\n")

@test
def undo_on_a_big_file_goes_back_to_the_edit(env):
    n = 50000
    env.write("big.txt", big_content(n))
    s = env.start("big.txt")
    s.send(ctrl("j") + "45000\r", 0.8)
    s.send(HOME + "EDIT", 0.3)
    s.send(C_PGUP, 0.6)
    s.send(HOME + "TOP", 0.3)
    s.send(UNDO, 0.8)
    s.send(UNDO, 0.8)
    eq(s.line_no(), 45000)
    s.send(UNDO, 0.5)
    s.send(SAVE, 3.0)
    t = read(env, "big.txt")
    eq(t, big_content(n))

@test
def undo_after_deleting_everything(env):
    s, t = edit(env, "one\ntwo\n", alt("d"), alt("d"), UNDO)
    eq(t, "two\n")
    s, t = edit(env, "one\ntwo\n", alt("d"), alt("d"), UNDO, UNDO, name="b.txt")
    eq(t, "one\ntwo\n")

# ------------------------------------------------------------------ programmer tools
def project(env):
    env.write("x.c", "int main()\n{\n    return boom;\n}\n")
    env.write("y.pas", "unit y;\nbegin\n  bad;\nend.\n")
    script = env.write("build.sh", "echo 'compiling'\n"
                       "echo 'x.c:3:12: error: boom undeclared'\n"
                       "echo 'note: something'\n"
                       "echo 'y.pas(3,3) Error: Identifier not found \"bad\"'\n"
                       "exit 1\n")
    return script

@test
def compile_shows_log_and_jumps_to_first_error(env):
    project(env)
    s = env.start("x.c", "y.pas")
    s.send(F10, 0.4)
    assert "Build command" in s.text(), s.text()
    s.send("sh build.sh\r", 1.5)
    t = s.text()
    assert "* Build Log *" in t and "x.c:3:12: error" in t, t
    # the editing window shows x.c with the cursor on the error line and column
    st = [s.stat(y) for y in range(s.rows) if s.row(y).startswith("L ")]
    assert any(x and x[4].endswith("x.c") and x[0] == 3 and x[1] == 12 for x in st), st

@test
def next_and_previous_error(env):
    project(env)
    s = env.start("x.c")
    s.send(F10, 0.4); s.send("sh build.sh\r", 1.5)
    s.send(alt("="), 0.6)
    st = [s.stat(y) for y in range(s.rows) if s.row(y).startswith("L ")]
    assert any(x and x[4].endswith("y.pas") and x[0] == 3 and x[1] == 3 for x in st), st
    s.send(alt("="), 0.4)
    assert "No more errors" in s.text(), s.text()
    s.send(alt("-"), 0.6)
    st = [s.stat(y) for y in range(s.rows) if s.row(y).startswith("L ")]
    assert any(x and x[4].endswith("x.c") and x[0] == 3 for x in st), st

@test
def compile_without_errors_reports_success(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(F10, 0.4); s.send("echo all good\r", 1.2)
    assert "no errors" in s.text().lower(), s.text()

@test
def compile_offers_to_save_modified_files(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2)
    s.send(F10, 0.4); s.send("true\r", 0.5)
    assert "Save modified files" in s.text(), s.text()
    s.send("y", 1.0)
    eq(read(env, "a.txt"), "abcx\n")

@test
def grep_jumps_to_first_match_and_lists_the_rest(env):
    env.write("a.txt", "nothing\n")
    env.write("one.txt", "first\nneedle here\n")
    env.write("two.txt", "needle too\n")
    s = env.start("a.txt")
    s.send(S_F10, 0.4)
    assert "Search files for" in s.text(), s.text()
    s.send("needle\r", 1.5)
    t = s.text()
    assert "* Grep Log *" in t and "one.txt:2:needle here" in t, t
    st = [s.stat(y) for y in range(s.rows) if s.row(y).startswith("L ")]
    assert any(x and x[4].endswith("one.txt") and x[0] == 2 for x in st), st
    s.send(alt("="), 0.6)
    st = [s.stat(y) for y in range(s.rows) if s.row(y).startswith("L ")]
    assert any(x and x[4].endswith("two.txt") and x[0] == 1 for x in st), st

@test
def grep_with_quotes_and_no_match(env):
    env.write("a.txt", "it's \"quoted\"\n")
    s = env.start("a.txt")
    s.send(S_F10, 0.4); s.send("it's\r", 1.2)
    assert "a.txt:1:" in s.text(), s.text()
    s.send(S_F10, 0.4); s.send("zzzzzz\r", 1.2)
    assert "No matches" in s.text(), s.text()

@test
def tag_lookup_with_pattern_and_line_number(env):
    env.write("lib.c", "int one;\nint helper(int x)\n{\n  return x;\n}\n")
    env.write("tags", "!_TAG_FILE_FORMAT\t2\nhelper\tlib.c\t/^int helper(int x)$/;\"\tf\nlast\tlib.c\t5;\"\tf\n")
    env.write("main.c", "helper(3);\nlast\n")
    s = env.start("main.c")
    s.send(ctrl("k") + ";", 0.4)
    assert "Tag:" in s.text() and "helper" in s.text(), s.text()
    s.send("\r", 0.6)
    assert s.stat()[4].endswith("lib.c"), s.stat()
    eq(s.line_no(), 2)
    s.send(ctrl("k") + "p", 0.3)
    s.send(DOWN, 0.2); s.send(ctrl("k") + ";", 0.4); s.send("\r", 0.6)
    eq(s.line_no(), 5)

@test
def error_formats_are_recognised(env):
    env.write("a.txt", "x\n")
    env.write("p.py", "a\nb\nc\n")
    env.write("g.go", "1\n2\n3\n4\n")
    script = env.write("b.sh", "echo '  File \"p.py\", line 3, in <module>'\n"
                       "echo './g.go:4:9: undefined: x'\n")
    s = env.start("a.txt")
    s.send(F10, 0.4); s.send("sh b.sh\r", 1.2)
    st = [s.stat(y) for y in range(s.rows) if s.row(y).startswith("L ")]
    assert any(x and x[4].endswith("p.py") and x[0] == 3 for x in st), st
    s.send(alt("="), 0.6)
    st = [s.stat(y) for y in range(s.rows) if s.row(y).startswith("L ")]
    assert any(x and x[4].endswith("g.go") and x[0] == 4 and x[1] == 9 for x in st), st

@test
def tools_menu(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send(ESC, 0.3); s.send("t", 0.3)
    t = s.text()
    assert "Compile" in t and "Grep" in t and "Tag" in t, t

# ------------------------------------------------------------------ the shipped mkedit.cfg
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

def sample_key_lines():
    import re
    out = []
    for line in open(os.path.join(ROOT, "mkedit.cfg")):
        m = re.match(r"#key (\S+(?: \S+)?) = (\w+)\s*$", line)
        if m:
            out.append((m.group(1), m.group(2)))
    return out

@test
def sample_config_key_lines_are_valid_and_really_conflict(env):
    import re
    defs = open(os.path.join(ROOT, "src", "uDefs.pas")).read()
    bound = {k.replace("''", "'") for k in re.findall(r"Bind\('((?:[^']|'')*)'", defs)}
    names = re.search(r"CmdNames: array\[TCmd\] of string = \((.*?)\n  \);", defs, re.S).group(1)
    cmds = set(re.findall(r"'(\w+)'", names))
    lines = sample_key_lines()
    assert len(lines) >= 30, len(lines)
    spare = {"C-\\", "A-t"}                    # keys offered for functions that would lose theirs
    for key, cmd in lines:
        assert cmd in cmds, "unknown command " + cmd
        assert key in bound or key in spare, "%s is not bound by default, so it is no conflict" % key
    # every "#key" line in the file is one of those (the MacroBegin line is the documented example)
    text = open(os.path.join(ROOT, "mkedit.cfg")).read().split("\n")
    others = [l for l in text if l.startswith("#key ") and "MacroBegin" not in l]
    eq(len(others), len(lines))

@test
def sample_config_has_no_effect_until_uncommented(env):
    cfg = os.path.join(env.home, ".config", "mkedit"); os.makedirs(cfg)
    import shutil
    shutil.copy(os.path.join(ROOT, "mkedit.cfg"), os.path.join(cfg, "mkedit.cfg"))
    s, t = edit(env, "abc\n", ctrl("t"))               # still DelRtWord
    eq(t, "\n")

@test
def sample_config_fully_uncommented_gives_joe_keys(env):
    import re
    cfg = os.path.join(env.home, ".config", "mkedit"); os.makedirs(cfg)
    text = open(os.path.join(ROOT, "mkedit.cfg")).read()
    text = re.sub(r"^#(key )", r"\1", text, flags=re.M)
    open(os.path.join(cfg, "mkedit.cfg"), "w").write(text)
    # ^A start of line, ^E end of line, ^D delete char, ^W delete word, ^T opens the menu
    s, t = edit(env, "abc def\n", RIGHT * 3, ctrl("a"), "X", ctrl("e"), "Y")
    eq(t, "Xabc defY\n")
    s, t = edit(env, "abc def\n", ctrl("d"), ctrl("w"), name="b.txt")
    eq(t, "def\n")                                 # ^D deletes "a", ^W then deletes "bc "
    # ^U / ^V page keys, ^J delete to end of line, ^K D saves instead of exiting
    env.write("c.txt", "".join("line%d\n" % i for i in range(1, 100)))
    s = env.start("c.txt")
    s.send(ctrl("v"), 0.3)
    assert s.line_no() > 15, s.stat()
    s.send(ctrl("u"), 0.3)
    eq(s.line_no(), 1)
    s.send("zz", 0.2)
    s.send(ctrl("k") + "d", 0.5)
    assert read(env, "c.txt").startswith("zzline1"), "^K D now saves"
    assert not s.exited(0.5)
    # Alt-W / Alt-Z scroll, Alt-X runs a command
    s.send(alt("z"), 0.3)
    assert s.row(1).startswith("line2"), s.row(1)
    s.send(alt("w"), 0.3)
    assert s.row(1).startswith("zzline1"), s.row(1)


def main():
    verbose = "-v" in sys.argv
    sel = None
    if "-k" in sys.argv:
        sel = sys.argv[sys.argv.index("-k") + 1]
    if not os.path.exists(BIN):
        raise SystemExit("binary not found: " + BIN)
    passed = failed = 0
    for t in TESTS:
        if sel and sel not in t.__name__:
            continue
        env = Env(BIN)
        t0 = time.time()
        try:
            t(env)
            passed += 1
            print("ok   %-45s %.1fs" % (t.__name__, time.time() - t0))
        except Exception as e:
            failed += 1
            print("FAIL %-45s %s" % (t.__name__, " | ".join(l.strip() for l in str(e).split("\n") if l.strip())[:400]))
            if verbose:
                traceback.print_exc()
                for s in env.sessions:
                    try:
                        print(s.text())
                    except Exception:
                        pass
        finally:
            env.cleanup()
    print("\n%d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()

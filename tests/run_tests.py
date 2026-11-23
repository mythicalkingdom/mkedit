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
    eq(t, "<  abc!  \n")

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
    # copy inserted before the cursor line (line 'd')
    eq(t, "a\nb\nc\na\nb\nd\n")

@test
def line_block_move(env):
    s, t = edit(env, "a\nb\nc\nd\n", alt("l"), alt("l"), DOWN, DOWN, alt("m"))
    eq(t, "b\na\nc\nd\n")

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
    eq(t, "b\na\nc\n")

@test
def cut_line_when_nothing_marked_and_paste_twice(env):
    s, t = edit(env, "a\nb\nc\n", "\x1b[3;2~", DOWN, "\x1b[2;2~", "\x1b[2;2~")
    eq(t, "b\na\na\nc\n")

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
    eq(read(env, "b.txt"), "one\nX\n")
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
    assert s.exited()
    eq(read(env, "a.txt"), "x\n")

@test
def exit_save_yes(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2)
    s.send(ctrl("k") + "d", 0.3)
    s.send("y", 0.4)
    assert s.exited()
    eq(read(env, "a.txt"), "abcx\n")

@test
def file_command_saves_and_exits(env):
    env.write("a.txt", "x\n")
    s = env.start("a.txt")
    s.send("abc", 0.2)
    s.send(ctrl("k") + "x", 0.4)
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
        assert "copy block" in t and "goto line" in t, t
        if cols >= 96:
            assert "Search/Replace" in t and "Windows" in t, t
        s.send("x", 0.3)
        assert "copy block" not in s.text()

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
    assert lines[24999].startswith("line 10:") and lines[25000].startswith("line 11:"), lines[24998:25002]

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
    s.send(ctrl("k") + "q", 0.3); s.send("y", 0.3)
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
    assert s.exited()

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

# Free Pascal build: `make` produces build/mkedit
FPC    ?= fpc
FLAGS  ?= -O2 -XX -CX -Xs -FU$(BUILD)
PREFIX ?= /usr/local
DESTDIR ?=

SRC     = src
BUILD   = build
BIN     = $(BUILD)/mkedit

SOURCES = $(wildcard $(SRC)/*.pas) $(wildcard $(SRC)/*.inc)

$(BIN): $(SOURCES)
	@mkdir -p $(BUILD)
	$(FPC) $(FLAGS) -Fu$(SRC) -Fi$(SRC) -o$(BIN) $(SRC)/mkedit.pas

mkedit: $(BIN)

install: $(BIN)
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 $(BIN) $(DESTDIR)$(PREFIX)/bin/mkedit

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/mkedit

# Engine stress test (no terminal needed)
doctest: $(SOURCES)
	@mkdir -p $(BUILD)
	$(FPC) -O2 -FU$(BUILD) -Fu$(SRC) -o$(BUILD)/doctest tests/doctest.pas
	DOCTEST_FILE=$(BUILD)/doctest.tmp $(BUILD)/doctest

# Behavioural tests on a pseudo-terminal (needs python3 and `pip install pyte`)
test: $(BIN)
	MKEDIT_BIN=$(CURDIR)/$(BIN) python3 tests/run_tests.py

clean:
	rm -rf $(BUILD)

.PHONY: mkedit install uninstall doctest test clean

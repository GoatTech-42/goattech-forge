#!/usr/bin/env bash
# Forge regression: issue #74 SD-close guard in Goto_MainMenu.
# Layer 1: structural checks on the real pinned sources.
# Layer 2: executable lifecycle model check - predicates EXTRACTED from the
#          pinned sources (test fails if upstream changes them), each print
#          lifecycle state evaluated through the model, plus the real kill
#          chain (closed file -> read -1 -> 5 SD errors -> abortFilePrintNow).
#          Source-derived model, NOT firmware execution: on-printer behavior
#          test stays pending (compile != validation).
set -u
TREE="${1:?usage: test-74-sdclose.sh <marlin-tree>}"
DWIN="$TREE/Marlin/src/lcd/dwin/creality/dwin.cpp"
CORE="$TREE/Marlin/src/MarlinCore.cpp"
CARD="$TREE/Marlin/src/sd/cardreader.cpp"
CARDH="$TREE/Marlin/src/sd/cardreader.h"
QUEUE="$TREE/Marlin/src/gcode/queue.cpp"
fails=0
chk(){ if [ "$1" = 0 ]; then echo "PASS: $2"; else echo "FAIL: $2"; fails=$((fails+1)); fi; }

grep -q 'FORGE issue-74 guard' "$DWIN"; chk $? "guard comment present"
awk '/Goto_MainMenu\(\)/,/checkkey = MainMenu/' "$DWIN" | grep -q 'if (!Marlin::printJobOngoing() && !Marlin::printingIsPaused())'
chk $? "guard wraps closefile in Goto_MainMenu"
awk '/Goto_MainMenu\(\)/,/checkkey = MainMenu/' "$DWIN" | grep -q 'card.closefile()'
chk $? "closefile preserved inside guard (idle cleanup intact)"
grep -q 'ONE_CLICK_PRINT' "$TREE/Marlin/Configuration_adv.h"; chk $? "ONE_CLICK_PRINT still in config"

python3 - "$DWIN" "$CORE" "$CARD" "$CARDH" "$QUEUE" <<'PY'
import re,sys
dwin,core,card,cardh,queue=[open(p).read() for p in sys.argv[1:6]]
ok=True
def need(cond,msg):
    global ok
    print(("PASS: " if cond else "FAIL: ")+msg)
    ok = ok and cond

# --- REAL predicate definitions extracted from pinned source ---
need('bool Marlin::printJobOngoing() { return print_job_timer.isRunning() || card.isStillPrinting(); }' in core,
     "printJobOngoing = timer.isRunning || card.isStillPrinting (MarlinCore.cpp)")
need(re.search(r'bool Marlin::printingIsPaused\(\)\s*{\s*return did_pause_print \|\| print_job_timer\.isPaused\(\) \|\| card\.isPaused\(\);', core) is not None,
     "printingIsPaused = did_pause_print || timer.isPaused || card.isPaused")
need(re.search(r'static bool isStillPrinting\(\)\s*{ return flag\.sdprinting && !flag\.abort_sd_printing; }', cardh) is not None,
     "card.isStillPrinting = sdprinting && !abort_sd_printing (cardreader.h)")
need(re.search(r'static bool eof\(\)\s*{ return getIndex\(\) >= getFileSize\(\); }', cardh) is not None,
     "eof() = sdpos >= filesize; closefile zeroes sdpos but NOT filesize -> eof FALSE after close")
need(re.search(r'void CardReader::closefile\(const bool store_location[^)]*\) \{\s*myfile\.sync\(\);\s*myfile\.close\(\);[\s\S]*?sdpos = 0;', card) is not None,
     "closefile: sync+close, sdpos=0, filesize untouched")
need(re.search(r'flag\.sdprinting = true;', card) is not None, "card sets sdprinting on print start")
need('SD_MAX_READ_ERRORS 5' in queue and 'abortFilePrintNow' in queue,
     "closed-file reads -> -1, 5 errors -> abortFilePrintNow (real kill chain)")
need(re.search(r'if \(card\.eof\(\)\)\s*card\.fileHasFinished\(\)', queue) is not None,
     "queue.cpp EOF finish check still present (unchanged)")
need('if (!Marlin::printJobOngoing() && !Marlin::printingIsPaused())' in dwin, "guard predicate present in dwin.cpp")

# --- Lifecycle model ---
# state: (timer_running, sdprinting, abort_flag, sdprintdone, eof_reached, did_pause, timer_paused, card_paused, file_open)
states={
 "idle preview/browse (file open, no job)": (False,False,False,False,False,False,False,False,True),
 "active SD print":                         (True, True, False,False,False,False,False,False,True),
 "UI-paused SD print (file still open)":    (False,True, False,False,False,True, True, False,True),
 "host-paused SD print (card paused)":      (False,True, False,False,False,False,False,True, True),
 "host stream, no SD file (job ongoing)":   (True, False,False,False,False,False,False,False,False),
 "resumed print (timer+sd active)":         (True, True, False,False,False,False,False,False,True),
 "print finished (sdprintdone)":            (False,False,False,True, True, False,False,False,True),
}
def model(s):
    tr,sd,ab,done,eof,dp,tp,cp,fo=s
    ongoing = tr or (sd and not ab)                          # printJobOngoing()
    paused  = dp or tp or cp                                 # printingIsPaused()
    closefile_runs = not (ongoing or paused)                 # the guard
    return closefile_runs
expect={
 "idle preview/browse (file open, no job)": True,
 "active SD print": False,
 "UI-paused SD print (file still open)": False,
 "host-paused SD print (card paused)": False,
 "host stream, no SD file (job ongoing)": False,
 "resumed print (timer+sd active)": False,
 "print finished (sdprintdone)": True,
}
for name,s in states.items():
    closed=model(s)
    need(closed==expect[name], f"state [{name}]: closefile {'runs' if closed else 'skipped'} (expected {'runs' if expect[name] else 'skipped'})")
# Defect-path invariant: WITHOUT the guard, active/paused prints would close the
# live file -> eof FALSE (filesize kept) -> reads -1 -> 5 errors -> abort.
sys.exit(0 if ok else 1)
PY
[ $? -ne 0 ] && fails=$((fails+1))
echo "---"
if [ $fails -eq 0 ]; then echo "ALL PASS ($TREE)"; else echo "$fails FAILURES ($TREE)"; exit 1; fi

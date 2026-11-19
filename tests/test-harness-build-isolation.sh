#!/usr/bin/env bash
# Regression test for harness/build-real.sh scratch isolation.
# build-real.sh promises it only works on a scratch copy of <marlin-tree>.
# This builds against disposable fixture trees whose Marlin/ is reached through
# symlinks (a symlinked Marlin/ root, and symlinked Configuration*.h files
# inside a real Marlin/) and checks that:
#   - the build succeeds,
#   - the files the symlinks point at are byte-identical before and after,
#   - a caller's Marlin/Config.h does not replace the host config.
# The fixtures are copies; the tree passed in is only read.
# Host build only: no hardware validation.
set -u
TREE="${1:?usage: test-harness-build-isolation.sh <marlin-tree containing Marlin/>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$TREE/Marlin/src/module/planner.cpp" ] || { echo "no Marlin/src/module/planner.cpp under $TREE" >&2; exit 1; }
F="$(mktemp -d)"; trap 'rm -rf "$F"' EXIT
fails=0
chk(){ if [ "$1" = 0 ]; then echo "PASS: $2"; else echo "FAIL: $2"; fails=$((fails+1)); fi; }
sums(){ sha256sum "$@" | awk '{print $1}'; }

# Fixture A: <fixture>/tree/Marlin is a symlink to a real directory elsewhere.
cp -r "$TREE/Marlin" "$F/real-marlin"
mkdir "$F/tree-a"; ln -s "$F/real-marlin" "$F/tree-a/Marlin"
before=$(sums "$F/real-marlin/Configuration.h" "$F/real-marlin/Configuration_adv.h")
bash "$ROOT/harness/build-real.sh" "$F/tree-a" "$F/out-a" >"$F/a.log" 2>&1
rc=$?; [ $rc = 0 ] || tail -n 15 "$F/a.log" | sed 's/^/  build: /'
chk $rc "build succeeds with a symlinked Marlin/ root"
after=$(sums "$F/real-marlin/Configuration.h" "$F/real-marlin/Configuration_adv.h")
[ "$before" = "$after" ]; chk $? "symlinked Marlin/ root: original Configuration.h and Configuration_adv.h unchanged"
cmp -s "$F/real-marlin/Configuration.h" "$TREE/Marlin/Configuration.h" && \
  cmp -s "$F/real-marlin/Configuration_adv.h" "$TREE/Marlin/Configuration_adv.h"
chk $? "symlinked Marlin/ root: fixture still matches the input tree"

# Fixture B: real Marlin/ dir whose Configuration*.h are symlinks to files elsewhere.
mkdir -p "$F/tree-b" "$F/cfg"
cp -r "$TREE/Marlin" "$F/tree-b/Marlin"
for c in Configuration.h Configuration_adv.h; do
  mv "$F/tree-b/Marlin/$c" "$F/cfg/$c"; ln -s "$F/cfg/$c" "$F/tree-b/Marlin/$c"
done
before=$(sums "$F/cfg/Configuration.h" "$F/cfg/Configuration_adv.h")
bash "$ROOT/harness/build-real.sh" "$F/tree-b" "$F/out-b" >"$F/b.log" 2>&1
rc=$?; [ $rc = 0 ] || tail -n 15 "$F/b.log" | sed 's/^/  build: /'
chk $rc "build succeeds with symlinked Configuration*.h"
after=$(sums "$F/cfg/Configuration.h" "$F/cfg/Configuration_adv.h")
[ "$before" = "$after" ]; chk $? "symlinked Configuration*.h: link targets unchanged"
[ -L "$F/tree-b/Marlin/Configuration.h" ] && [ -L "$F/tree-b/Marlin/Configuration_adv.h" ]
chk $? "symlinked Configuration*.h: links left in place"

# Fixture C: the caller's tree has a Marlin/Config.h. Marlin's include chain
# prefers Config.h over Configuration*.h, so it must not reach the scratch copy.
mkdir "$F/tree-c"; cp -r "$TREE/Marlin" "$F/tree-c/Marlin"
printf '#error "caller Marlin/Config.h reached the harness build"\n' >"$F/tree-c/Marlin/Config.h"
before=$(sums "$F/tree-c/Marlin/Config.h")
bash "$ROOT/harness/build-real.sh" "$F/tree-c" "$F/out-c" >"$F/c.log" 2>&1
rc=$?; [ $rc = 0 ] || tail -n 15 "$F/c.log" | sed 's/^/  build: /'
chk $rc "caller Marlin/Config.h is ignored; host config is compiled"
[ "$before" = "$(sums "$F/tree-c/Marlin/Config.h")" ]; chk $? "caller Marlin/Config.h left untouched"

[ $fails = 0 ] && echo "RESULT: all checks passed" || echo "RESULT: $fails failure(s)"
[ $fails = 0 ]

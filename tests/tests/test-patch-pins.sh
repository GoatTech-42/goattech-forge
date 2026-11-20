#!/usr/bin/env bash
# Offline patch-pin contract. No compiler, network or firmware binaries.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import pathlib, sys
root=pathlib.Path(sys.argv[1])
s=(root/'.github/workflows/patch-chain-tests.yml').read_text()
check='python3 scripts/verify-patch-pins.py'
apply='git -C "$RUNNER_TEMP/marlin" apply --check'
assert check in s and s.index(check) < s.index(apply), 'CI must verify patch pins before applying patches'
print('PASS: CI verifies patch pins before applying them')
PY
python3 "$ROOT/tests/test_patch_pins.py"

#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "SELF-TEST FAILED at line $LINENO (command: $BASH_COMMAND)" >&2' ERR

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for script in "$ROOT"/linux/*.sh "$ROOT"/tests/*.sh; do
  bash -n "$script"
done

if ! bash -x "$ROOT/linux/nomad-audit.sh" "$TMP/audit" >"$TMP/audit.log" 2>&1; then cat "$TMP/audit.log"; exit 1; fi
test -s "$TMP/audit/nomad-hardware-report.txt"
grep -q "READ-ONLY AUDIT" "$TMP/audit/nomad-hardware-report.txt"

if command -v python3 >/dev/null 2>&1 && test -s "$TMP/audit/nomad-hardware-report.json"; then
  python3 - "$TMP/audit/nomad-hardware-report.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    report = json.load(f)
assert report.get("read_only") is True
assert isinstance(report.get("blockdevices"), list)
assert "system" in report and "cpu" in report and "memory" in report
print("JSON report: valid")
PY
fi

grep -q 'This utility will not partition, format, erase, or install anything' "$ROOT/linux/nomad-propose.sh"
grep -q 'No target will be guessed' "$ROOT/linux/nomad-propose.sh"

echo "N.O.M.A.D. self-test passed."

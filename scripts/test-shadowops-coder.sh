#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/scripts/shadowops-coder.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_BIN="$TMP/bin"
WORK="$TMP/work"
mkdir -p "$FAKE_BIN" "$WORK"

cat >"$FAKE_BIN/ollama" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "list" ]]; then
  cat <<'OUT'
NAME                    ID              SIZE
qwen2.5-coder:14b       fake            9 GB
qwen2.5-coder:7b        fake            5 GB
OUT
  exit 0
fi
exit 1
EOF
chmod +x "$FAKE_BIN/ollama"

cat >"$FAKE_BIN/opencode" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$TMP/opencode.args"
exit 0
EOF
chmod +x "$FAKE_BIN/opencode"

export PATH="$FAKE_BIN:$PATH"

git -C "$WORK" init -q -b main

echo "test" >"$WORK/README.md"
git -C "$WORK" add README.md
git -C "$WORK" -c user.name=test -c user.email=test@example.invalid commit -q -m init

set +e
(
  cd "$WORK"
  "$LAUNCHER" "do nothing"
) >"$TMP/main.out" 2>"$TMP/main.err"
MAIN_RC=$?
set -e

if [[ $MAIN_RC -eq 0 ]] || ! grep -q 'BLOCKED_PROTECTED_BRANCH' "$TMP/main.err"; then
  echo "protected branch gate failed" >&2
  exit 1
fi

git -C "$WORK" switch -q -c test/coder
(
  cd "$WORK"
  "$LAUNCHER" "implement a safe test change"
) >"$TMP/feature.out" 2>"$TMP/feature.err"

grep -Fxq 'run' "$TMP/opencode.args"
grep -Fxq -- '--agent' "$TMP/opencode.args"
grep -Fxq 'shadowops-coder' "$TMP/opencode.args"
grep -Fxq -- '--model' "$TMP/opencode.args"
grep -Fxq 'ollama/qwen2.5-coder:14b' "$TMP/opencode.args"
grep -Fxq 'implement a safe test change' "$TMP/opencode.args"

echo "SHADOWOPS_CODER_CONTRACT=PASS"

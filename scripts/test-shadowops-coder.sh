#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/scripts/shadowops-coder.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_BIN="$TMP/bin"
WORK="$TMP/work"
mkdir -p "$FAKE_BIN" "$WORK"

cat >"$FAKE_BIN/opencode" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  models)
    printf '%s\n' 'remote/test-model'
    exit 0
    ;;
  run)
    printf '%s\n' "\$@" >"$TMP/opencode.args"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$FAKE_BIN/opencode"

export PATH="$FAKE_BIN:$PATH"
export SHADOWOPS_STATE_DIR="$TMP/state"

git -C "$WORK" init -q -b main

echo "test" >"$WORK/README.md"
git -C "$WORK" add README.md
git -C "$WORK" -c user.name=test -c user.email=test@example.invalid commit -q -m init

set +e
(
  cd "$WORK"
  SHADOWOPS_CODER_MODEL='remote/test-model' "$LAUNCHER" "do nothing"
) >"$TMP/main.out" 2>"$TMP/main.err"
MAIN_RC=$?
set -e

if [[ $MAIN_RC -eq 0 ]] || ! grep -q 'BLOCKED_PROTECTED_BRANCH' "$TMP/main.err"; then
  echo "protected branch gate failed" >&2
  exit 1
fi

git -C "$WORK" switch -q -c test/coder

set +e
(
  cd "$WORK"
  "$LAUNCHER" "implement a safe test change"
) >"$TMP/no-model.out" 2>"$TMP/no-model.err"
NO_MODEL_RC=$?
set -e
if [[ $NO_MODEL_RC -eq 0 ]] || ! grep -q 'BLOCKED_REMOTE_MODEL_REQUIRED' "$TMP/no-model.err"; then
  echo "missing remote model gate failed" >&2
  exit 1
fi

set +e
(
  cd "$WORK"
  SHADOWOPS_CODER_MODEL='ollama/qwen2.5-coder:14b' "$LAUNCHER" "implement a safe test change"
) >"$TMP/local-model.out" 2>"$TMP/local-model.err"
LOCAL_MODEL_RC=$?
set -e
if [[ $LOCAL_MODEL_RC -eq 0 ]] || ! grep -q 'BLOCKED_LOCAL_AI_FORBIDDEN' "$TMP/local-model.err"; then
  echo "local AI block failed" >&2
  exit 1
fi

(
  cd "$WORK"
  SHADOWOPS_CODER_MODEL='remote/test-model' "$LAUNCHER" "implement a safe test change"
) >"$TMP/feature.out" 2>"$TMP/feature.err"

grep -Fxq 'run' "$TMP/opencode.args"
grep -Fxq -- '--agent' "$TMP/opencode.args"
grep -Fxq 'shadowops-coder' "$TMP/opencode.args"
grep -Fxq -- '--model' "$TMP/opencode.args"
grep -Fxq 'remote/test-model' "$TMP/opencode.args"
grep -Fxq 'implement a safe test change' "$TMP/opencode.args"

if grep -Eiq 'ollama|lmstudio|llamacpp|llama\.cpp' "$TMP/opencode.args"; then
  echo "local provider leaked into remote-only launch" >&2
  exit 1
fi

echo "AI_EXECUTION_POLICY=REMOTE_ONLY"
echo "SHADOWOPS_CODER_CONTRACT=PASS"

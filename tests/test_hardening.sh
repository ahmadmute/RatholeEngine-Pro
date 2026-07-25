#!/usr/bin/env bash
# Regression tests for v1.5.1 hardening.
set -euo pipefail
ok(){ echo "ok - $*"; }
fail(){ echo "not ok - $*" >&2; exit 1; }
ROOT_REPO="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Shared port validation must reject syntactically numeric but invalid TCP/UDP ports.
(
  source "$ROOT_REPO/rathole-manager/common.sh"
  valid_port 1 && valid_port 65535 || fail 'valid port rejected'
  for p in 0 65536 99999 -1 abc ''; do
    valid_port "$p" && fail "invalid port accepted: $p"
  done
  valid_host_port panel.example:443 || fail 'valid host:port rejected'
  valid_host_port panel.example:99999 && fail 'invalid endpoint port accepted'
  ok 'port/endpoint validation is range-safe'
)

# A jq failure must never replace state.json with empty/partial data.
(
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  printf '{"control_port":2333,"nodes":[]}\n' > "$T/state.json"
  mkdir "$T/bin"
  cat > "$T/bin/jq" <<'EOF'
#!/usr/bin/env bash
exit 23
EOF
  chmod +x "$T/bin/jq"
  before="$(sha256sum "$T/state.json" | awk '{print $1}')"
  set +e
  PATH="$T/bin:$PATH" RATHOLECTL_LIB_ONLY=1 STATE="$T/state.json" \
    bash -c 'source "$1/rathole-manager/ratholectl"; state_set ".control_port" 4444 num' _ "$ROOT_REPO" >/dev/null 2>&1
  rc=$?
  set -e
  after="$(sha256sum "$T/state.json" | awk '{print $1}')"
  [ "$rc" -ne 0 ] || fail 'state_set should fail when jq fails'
  [ "$before" = "$after" ] || fail 'state.json changed after jq failure'
  python3 -m json.tool "$T/state.json" >/dev/null || fail 'state.json became invalid'
  ok 'state update is failure-atomic'
)

# Release installer must verify downloaded assets when SHA256SUMS is available.
grep -q 'SHA256SUMS.selected' "$ROOT_REPO/install.sh" || fail 'release checksum verification missing'
grep -q 'dist/SHA256SUMS' "$ROOT_REPO/.github/workflows/release.yml" || fail 'release checksum asset missing'
ok 'release asset checksum verification is wired'


# 4) bootstrap archive extraction must reject path traversal before root extraction.
TMP_AR="$(mktemp -d)"
trap 'rm -rf "$TMP_AR"' EXIT
mkdir -p "$TMP_AR/safe/rathole-manager"
printf '#!/bin/sh\n' > "$TMP_AR/safe/rathole-manager/install-panel.sh"
( cd "$TMP_AR/safe" && zip -qr "$TMP_AR/safe.zip" rathole-manager )
python3 - "$TMP_AR/bad.zip" <<'PY2'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr('../escape.txt', 'owned')
    z.writestr('rathole-manager/install-panel.sh', '#!/bin/sh\n')
PY2
(
  export BOOTSTRAP_LIB_ONLY=1
  source "$ROOT_REPO/bootstrap.sh"
  extract "$TMP_AR/safe.zip" "$TMP_AR/out-safe"
  [ -f "$TMP_AR/out-safe/rathole-manager/install-panel.sh" ]
)
if (
  export BOOTSTRAP_LIB_ONLY=1
  source "$ROOT_REPO/bootstrap.sh"
  extract "$TMP_AR/bad.zip" "$TMP_AR/out-bad"
) >/dev/null 2>&1; then
  echo "FAIL: bootstrap path traversal archive ra ghabool kard" >&2
  exit 1
fi
[ ! -e "$TMP_AR/escape.txt" ] || { echo "FAIL: archive az sandbox kharej nevesht" >&2; exit 1; }
echo "ok - bootstrap archive traversal reject shod"

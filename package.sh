#!/usr/bin/env bash
# package.sh — sakht baste-ye rathole-manager.zip bhsvrt dorost (forward-slash, LF)
# rooye linvks/mk ejra kon:  bash package.sh
# nokte: zip sakhthshdh ba Windows Compress-Archive az backslash estefade mikonad ke unzip
#       linvks drbarhash hoshdar midhd; in askript ba abzar zip dorost misazad.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]:-$0}")"

SRC="rathole-manager"
OUT_ZIP="rathole-manager.zip"
OUT_TAR="rathole-manager.tar.gz"
[ -d "$SRC" ] || { echo "pvshh $SRC peyda nashod."; exit 1; }

# barresi core binary: agar RATHOLE_REQUIRE_CORE=1 bashad va binary-ha vojood nadashtand → fail
RATHOLE_REQUIRE_CORE="${RATHOLE_REQUIRE_CORE:-0}"
CORE_OK=0
if [ -f "$SRC/core/SHA256SUMS" ] && \
   [ -f "$SRC/core/x86_64-unknown-linux-gnu/rathole" ] && \
   [ -f "$SRC/core/aarch64-unknown-linux-gnu/rathole" ]; then
  CORE_OK=1
fi
if [ "$RATHOLE_REQUIRE_CORE" = "1" ] && [ "$CORE_OK" -eq 0 ]; then
  echo "[!] RATHOLE_REQUIRE_CORE=1 set shode vali core binary-ha dar rathole-manager/core/ peyda nashod."
  echo "    avval core/build.sh ra ejra kon ya az workflow artifact download kon."
  exit 1
elif [ "$CORE_OK" -eq 0 ]; then
  echo "[*] core binary-ha dar bundle nistnd (baraye release az RATHOLE_REQUIRE_CORE=1 estefade kon)."
fi

# pvshh-ye mstndat (docs/) ham dar baste gonjande mishavad agar vojood dashte bashad.
DOCS="docs"
PACK=("$SRC")
[ -d "$DOCS" ] && PACK+=("$DOCS")

echo "[+] normal-sazi khate-payan (LF) rooye askriptha va mstndat..."
find "${PACK[@]}" -type f \( -name '*.sh' -o -name '*.md' -o -name 'common.sh' -o -name 'ratholectl' -o -name 'ratholenode' \) \
  -exec sed -i 's/\r$//' {} +
# ghabele-ejra kardan askriptha
for s in "$SRC"/*.sh "$SRC/ratholectl" "$SRC/ratholenode"; do [ -f "$s" ] && chmod +x "$s"; done

rm -f "$OUT_ZIP" "$OUT_TAR"

# tar.gz hamishe sakhte mishavad ta release asset-ha sabet va ghabele-pishbini bashand.
echo "[+] sakht $OUT_TAR..."
tar -czf "$OUT_TAR" "${PACK[@]}"

if command -v zip >/dev/null 2>&1; then
  echo "[+] sakht $OUT_ZIP ba zip (forward-slash)..."
  zip -r -q "$OUT_ZIP" "${PACK[@]}"
else
  echo "[!] zip nasb nist; baraye release-e kamel package-e zip lazem ast." >&2
  exit 1
fi

# etebarsanji: nbaid hich backslash ya path-e khatarnaak dar namha bashad.
if command -v unzip >/dev/null 2>&1; then
  if unzip -Z1 "$OUT_ZIP" | grep -q '\\'; then
    echo "[!] hoshdar: backslash dar namha peyda shod!"; exit 1
  fi
  if unzip -Z1 "$OUT_ZIP" | awk 'BEGIN{bad=0} /^\//{bad=1} {gsub(/\\/,"/"); n=split($0,a,"/"); for(i=1;i<=n;i++) if(a[i]=="..") bad=1} END{exit bad?0:1}'; then
    echo "[!] path-e khatarnaak dar zip peyda shod!"; exit 1
  fi
fi

echo "[+] basteha sakhte shodand:"
ls -lh "$OUT_ZIP" "$OUT_TAR"

#!/usr/bin/env bash
# harns tst mahalli baraye ratholectl bedoon niaz be root/systemd/nginx vaghai
set -uo pipefail

BASE="${RATHOLE_MANAGER_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/etc/rathole" "$ROOT/etc/rathole-manager" "$ROOT/etc/nginx/conf.d" "$ROOT/etc/nginx/stream.d"
command -v jq >/dev/null 2>&1 || { echo "jq lazem ast" >&2; exit 1; }
echo "sandbox: $ROOT ; jq: $(jq --version)"

# wrapper: masirha ra ghabl az source override mikonad; library mode az ejra-ye main jelogiri mikonad.
RUN="$ROOT/run.sh"
cat > "$RUN" <<EOF
#!/usr/bin/env bash
set -uo pipefail
export RATHOLECTL_LIB_ONLY=1
export STATE="$ROOT/etc/rathole-manager/state.json"
export SERVER_TOML="$ROOT/etc/rathole/server.toml"
export NOISE_TOML="$ROOT/etc/rathole/noise-server.toml"
export NGINX_CONF="$ROOT/etc/nginx/conf.d/rathole.conf"
export STREAM_CONF="$ROOT/etc/nginx/stream.d/rathole-stream.conf"
source "$BASE/ratholectl"
# khonsa-sazi tavabe-ye system-e vaghei; hich file-i birun az sandbox taghir nemikonad.
need_root(){ :; }
nginx(){ return 0; }
systemctl(){ return 0; }
ensure_stream_include(){ :; }
"\$@"
EOF
chmod +x "$RUN"

line(){ echo "=============================================="; echo "$*"; echo "=============================================="; }

line "tst 1: init gheyre-taamoli"
# init flag-based ast ta harness dar CI va shell-haye bedoon controlling TTY paydar bemanad.
touch "$ROOT/fullchain.pem" "$ROOT/privkey.pem"
bash "$RUN" cmd_init \
  --domain btli.ir \
  --fullchain "$ROOT/fullchain.pem" \
  --key "$ROOT/privkey.pem" \
  --control-port 2333 \
  --fake-port 8080 \
  --sub-port 2096 \
  --data-start 1001 \
  --api-start 7001 \
  --nginx-conf "$ROOT/etc/nginx/conf.d/rathole.conf"
echo "--- state.json ---"; jq . "$ROOT/etc/rathole-manager/state.json"

line "tst 2: afzoodan se node (usa01 ba api)"
bash "$RUN" cmd_add trk01 2087
bash "$RUN" cmd_add nld01 2087
bash "$RUN" cmd_add usa01 2087 62050
echo "--- list nodeha ---"; bash "$RUN" cmd_ls

line "tst 3: server.toml tvlidshdh"
cat "$ROOT/etc/rathole/server.toml"

line "tst 4: config nginx tvlidshdh"
cat "$ROOT/etc/nginx/conf.d/rathole.conf"

line "tst 5: hazf node nld01 va baztolid"
bash "$RUN" cmd_rm nld01
echo "--- map baad az hazf ---"; sed -n '/map \$uri/,/}/p' "$ROOT/etc/nginx/conf.d/rathole.conf"

line "tst 6: tkhsis port azad (bayad 1002 azadshdh ra bgird)"
bash "$RUN" cmd_add pol01 2087
bash "$RUN" cmd_ls

line "tst 7: jlvgiri az name tekrari"
bash "$RUN" cmd_add trk01 9999 || echo "OK: name tekrari rad shod"

line "tst 8: direct_port dar set-e rezerv (node nabayad port-e direct ra begirad)"
# aval port-e azad-e badi ra keshf kon (yek node-e movaghat bezar, port-esh ra bardar, hazfesh kon).
# sepas hamon port ra be onvan direct_port rezerv kon; node-e vaghai bayad an ra RAD konad va port-e digari begirad.
bash "$RUN" cmd_add probe01 2087
NEXT="$(jq -r '.nodes[]|select(.name=="probe01")|.port' "$ROOT/etc/rathole-manager/state.json")"
bash "$RUN" cmd_rm probe01
jq --argjson p "$NEXT" '.direct_port=$p' "$ROOT/etc/rathole-manager/state.json" > "$ROOT/s.tmp" && mv "$ROOT/s.tmp" "$ROOT/etc/rathole-manager/state.json"
bash "$RUN" cmd_add rez01 2087
GOT="$(jq -r '.nodes[]|select(.name=="rez01")|.port' "$ROOT/etc/rathole-manager/state.json")"
[ "$GOT" != "$NEXT" ] && echo "OK: node port ($GOT) ba direct_port ($NEXT) tadakhol nadarad" || echo "FAIL: node port ba direct_port ($NEXT) yeksan ast"

line "tst 9: direct on (halat standalone) — map va server block"
jq 'del(.direct_port,.direct_header,.plain_port)' "$ROOT/etc/rathole-manager/state.json" > "$ROOT/s.tmp" && mv "$ROOT/s.tmp" "$ROOT/etc/rathole-manager/state.json"
jq '.direct_port=8081 | .direct_header="X-Cdn-Id"' "$ROOT/etc/rathole-manager/state.json" > "$ROOT/s.tmp" && mv "$ROOT/s.tmp" "$ROOT/etc/rathole-manager/state.json"
bash "$RUN" regenerate
CONF="$ROOT/etc/nginx/conf.d/rathole.conf"
grep -q 'map \$http_x_cdn_id \$direct_node' "$CONF" && echo "OK: map 1 (\$http var) hast" || echo "FAIL: map 1 nist"
grep -q 'map \$direct_node \$direct_backend' "$CONF" && echo "OK: map 2 hast" || echo "FAIL: map 2 nist"
grep -qE '^\s*listen 8081;' "$CONF" && echo "OK: listen 8081 hast" || echo "FAIL: listen 8081 nist"
grep -q 'proxy_pass http://127.0.0.1:\$direct_backend;' "$CONF" && echo "OK: proxy_pass direct_backend" || echo "FAIL: proxy_pass direct_backend nist"
# node-e non-SNI bayad dar map 1 bashad; trk01 az tst 2 hast
grep -qE '"trk01"\s+[0-9]+;' "$CONF" && echo "OK: trk01 dar map" || echo "FAIL: trk01 dar map nist"

line "tst 10: header-e delkhah -> motaghayer-e \$http dorost"
jq '.direct_header="X-My-Route"' "$ROOT/etc/rathole-manager/state.json" > "$ROOT/s.tmp" && mv "$ROOT/s.tmp" "$ROOT/etc/rathole-manager/state.json"
bash "$RUN" regenerate
grep -q 'map \$http_x_my_route \$direct_node' "$CONF" && echo "OK: X-My-Route -> \$http_x_my_route" || echo "FAIL: transform-e header ghalat"
# baazgardandan be pishfarz baraye testhaye baadi
jq '.direct_header="X-Cdn-Id"' "$ROOT/etc/rathole-manager/state.json" > "$ROOT/s.tmp" && mv "$ROOT/s.tmp" "$ROOT/etc/rathole-manager/state.json"

line "tst 11: node-e SNI dar map-e direct nabashad"
bash "$RUN" cmd_add gm01 2087 2>/dev/null
jq '(.nodes[]|select(.name=="gm01")|.sni)="ex.com"' "$ROOT/etc/rathole-manager/state.json" > "$ROOT/s.tmp" && mv "$ROOT/s.tmp" "$ROOT/etc/rathole-manager/state.json"
bash "$RUN" regenerate
sed -n '/map \$http_x_cdn_id \$direct_node/,/}/p' "$CONF" | grep -q '"gm01"' && echo "FAIL: node SNI dar map" || echo "OK: node SNI hazf shod az map"

line "tst 12: direct_port == plain_port -> yek block (bedoon duplicate listen)"
jq 'del(.direct_port,.direct_header) | .plain_port=9000 | .direct_port=9000 | .direct_header="X-Cdn-Id"' "$ROOT/etc/rathole-manager/state.json" > "$ROOT/s.tmp" && mv "$ROOT/s.tmp" "$ROOT/etc/rathole-manager/state.json"
bash "$RUN" regenerate
# faghat yek 'listen 9000;' bayad bashad
CNT="$(grep -cE '^\s*listen 9000;' "$CONF")"
[ "$CNT" = "1" ] && echo "OK: yek listen 9000" || echo "FAIL: $CNT listen 9000 (duplicate)"
# map 2 branch-e khali bayad be $backend_port bashad, na fake_port
sed -n '/map \$direct_node \$direct_backend/,/}/p' "$CONF" | grep -qE '""\s+\$backend_port;' && echo "OK: fallback = backend_port (fall-through)" || echo "FAIL: fallback ghalat"
# location plain bayad be direct_backend proxy konad
awk '/listen 9000;/{f=1} f&&/proxy_pass http:\/\/127.0.0.1:\$direct_backend;/{print "found"; exit}' "$CONF" | grep -q found && echo "OK: plain location -> direct_backend" || echo "FAIL: plain location -> direct_backend nist"

line "tst 13: regression — plain-only (bedoon direct) hanooz backend_port"
jq 'del(.direct_port,.direct_header) | .plain_port=8880' "$ROOT/etc/rathole-manager/state.json" > "$ROOT/s.tmp" && mv "$ROOT/s.tmp" "$ROOT/etc/rathole-manager/state.json"
bash "$RUN" regenerate
awk '/listen 8880;/{f=1} f&&/proxy_pass http:\/\/127.0.0.1:\$backend_port;/{print "found"; exit}' "$CONF" | grep -q found && echo "OK: plain-only -> backend_port" || echo "FAIL: plain-only regression"
grep -q 'map .* \$direct_node' "$CONF" && echo "FAIL: map direct baraye plain-only tvlid shod" || echo "OK: bedoon direct, map direct nist"

line "tst 14: cmd_direct on/status/off"
jq 'del(.direct_port,.direct_header,.plain_port)' "$ROOT/etc/rathole-manager/state.json" > "$ROOT/s.tmp" && mv "$ROOT/s.tmp" "$ROOT/etc/rathole-manager/state.json"
bash "$RUN" cmd_direct on --port 8081 --header X-Cdn-Id >/dev/null
GP="$(jq -r '.direct_port' "$ROOT/etc/rathole-manager/state.json")"; GH="$(jq -r '.direct_header' "$ROOT/etc/rathole-manager/state.json")"
[ "$GP" = "8081" ] && [ "$GH" = "X-Cdn-Id" ] && echo "OK: state direct set shod" || echo "FAIL: state ghalat ($GP/$GH)"
# stdout ra capture mikonim (pipe be grep -q zir-e pipefail be khatere SIGPIPE 141 midahad).
DST="$(bash "$RUN" cmd_direct status)"
echo "$DST" | grep -q 'roshan' && echo "OK: status roshan" || echo "FAIL: status"
echo "$DST" | grep -q 'trk01 -> "X-Cdn-Id: trk01"' && echo "OK: per-node header dar status" || echo "FAIL: per-node header nist"
bash "$RUN" cmd_direct on --port 443 2>/dev/null && echo "FAIL: port 443 ghabool shod" || echo "OK: port 443 rad shod"
bash "$RUN" cmd_direct on --header 'bad;header' 2>/dev/null && echo "FAIL: header ghalat ghabool shod" || echo "OK: header ghalat rad shod"
bash "$RUN" cmd_direct off >/dev/null
jq -e '.direct_port // empty' "$ROOT/etc/rathole-manager/state.json" >/dev/null 2>&1 && echo "FAIL: direct_port baad az off munde" || echo "OK: off pak kard"

echo "SANDBOX=$ROOT"

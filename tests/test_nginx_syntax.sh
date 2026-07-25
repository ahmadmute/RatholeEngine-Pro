#!/usr/bin/env bash
# Real nginx parser smoke test for the generated HTTP/WebSocket/hub config.
set -euo pipefail
ok(){ echo "ok - $*"; }
fail(){ echo "not ok - $*" >&2; exit 1; }
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
for b in nginx openssl jq; do command -v "$b" >/dev/null 2>&1 || { echo "ok - skip: $b is not installed"; exit 0; }; done
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=panel.test' \
  -keyout "$T/key.pem" -out "$T/cert.pem" >/dev/null 2>&1
jq -n --arg fc "$T/cert.pem" --arg key "$T/key.pem" --arg nc "$T/rathole.conf" '{
 domain:"panel.test",cert_fullchain:$fc,cert_key:$key,nginx_conf:$nc,
 control_port:2333,control_path:"/_rh/deadbeefdeadbeefdeadbeefdeadbeef",
 fake_port:8080,sub_port:2096,internal_port:8443,hub_port:8088,
 nodes:[{name:"trk01",port:1001,inbound_port:2087,token:"0123456789abcdef"}]
}' > "$T/state.json"
RATHOLECTL_LIB_ONLY=1 STATE="$T/state.json" NGINX_CONF="$T/rathole.conf" STREAM_CONF="$T/stream.conf" \
  bash -c 'source "$1/rathole-manager/ratholectl"; gen_nginx_conf' _ "$REPO_ROOT"
cat > "$T/nginx.conf" <<EOF
worker_processes 1;
pid $T/nginx.pid;
error_log $T/error.log;
events { worker_connections 64; }
http {
  access_log off;
  map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }
  include $T/rathole.conf;
}
EOF
nginx -t -p "$T" -c "$T/nginx.conf" >/dev/null 2>&1 || { cat "$T/error.log" >&2 || true; fail 'generated nginx config failed nginx -t'; }
grep -q 'proxy_set_header X-Forwarded-Proto \$scheme;' "$T/rathole.conf" || fail 'hub proxy scheme header missing'
grep -q 'location = /_rh/deadbeefdeadbeefdeadbeefdeadbeef' "$T/rathole.conf" || fail 'secret control path missing'
ok 'generated nginx config passes real nginx -t'

#!/bin/sh
# Installer for a transport-selectable singbox-lite Argo manager.
set -eu
umask 077
UPSTREAM_REF=f5143fe49256ae71cd013b2717ea83cfa3a8b8ec
BASE=/usr/local/lib/argo-auto
MANAGER=/usr/local/bin/sb-argo-auto
SETTINGS=/usr/local/etc/sing-box/argo-transport
mode= transport=auto
usage() {
 cat <<'EOF'
Usage: sh install.sh --mode temp|fixed [--transport auto|http2|quic]
       sh install.sh --help
Default transport: auto. Fixed mode prompts for Tunnel Token and hostname.
Re-running installs the manager and CREATES ANOTHER NODE; use sb-argo-auto
for subsequent management. Transport setting applies to ALL Argo nodes
started by this manager, including its keepalive jobs, on their next start.
EOF
}
while [ "$#" -gt 0 ]; do
 case "$1" in
  --mode) [ "$#" -ge 2 ] || exit 2; mode=$2; shift 2;;
  --transport) [ "$#" -ge 2 ] || exit 2; transport=$2; shift 2;;
  --help|-h) usage; exit 0;;
  *) usage >&2; exit 2;;
 esac
done
case "$mode" in temp|fixed) ;; *) usage >&2; exit 2;; esac
case "$transport" in auto|http2|quic) ;; *) usage >&2; exit 2;; esac
[ "$(id -u)" = 0 ] || { echo 'Run as root.' >&2; exit 1; }
if ! command -v bash >/dev/null || ! command -v curl >/dev/null; then
 if command -v apk >/dev/null; then apk add --no-cache bash curl ca-certificates
 elif command -v apt-get >/dev/null; then apt-get update; apt-get install -y bash curl ca-certificates
 else echo 'Install bash, curl and CA certificates first.' >&2; exit 1; fi
fi
# BusyBox may expose crontab without an OpenRC cron service. Install both
# explicitly on Alpine so upstream can enable its Argo keepalive job.
if command -v apk >/dev/null; then
 apk add --no-cache dcron
fi
mkdir -p "$BASE" /usr/local/etc/sing-box
chmod 700 "$BASE"
work=$(mktemp -d "$BASE/build.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
curl --proto '=https' --tlsv1.2 -fLsS --retry 3 --connect-timeout 15 --max-time 120 \
 "https://raw.githubusercontent.com/0xdabiaoge/singbox-lite/$UPSTREAM_REF/singbox.sh" -o "$work/upstream.sh"
# Fail closed rather than silently patch an unexpected upstream revision.
[ "$(grep -c -- '--protocol http2' "$work/upstream.sh")" = 2 ] || { echo 'Unexpected transport call sites.' >&2; exit 1; }
[ "$(grep -c '^    _main_menu$' "$work/upstream.sh")" = 1 ] || exit 1
[ "$(grep -c 'read -p .* tunnel_mode$' "$work/upstream.sh")" = 1 ] || exit 1
cat > "$work/extension" <<'EOF'

# Argo-Script extension: persist transport for future keepalive/restarts.
ARGO_TRANSPORT_PROTOCOL=auto
if [ -f /usr/local/etc/sing-box/argo-transport ]; then
    IFS= read -r ARGO_TRANSPORT_PROTOCOL < /usr/local/etc/sing-box/argo-transport || true
fi
case "$ARGO_TRANSPORT_PROTOCOL" in auto|http2|quic) ;;
    *) echo 'Invalid argo-transport value; expected auto/http2/quic.' >&2; exit 2;;
esac
export ARGO_TRANSPORT_PROTOCOL
_argo_auto_entry() {
    case "${ARGO_INSTALL_MODE:-}" in
        temp|fixed)
            # Existing cores are retained; only missing cores are installed.
            if [ ! -x "$SINGBOX_BIN" ]; then
                _do_update_singbox "$SINGBOX_FIXED_VERSION" || return 1
            fi
            _add_argo_vless_ws
            ;;
        '') _main_menu;;
        *) echo 'Invalid install mode.' >&2; return 2;;
    esac
}
EOF
sed -e '/^umask 077$/r '"$work/extension" \
 -e 's/--protocol http2/--protocol "${ARGO_TRANSPORT_PROTOCOL}"/g' \
 -e 's/^    _main_menu$/    _argo_auto_entry/' \
 -e '/read -p .* tunnel_mode$/c\
    case "${ARGO_INSTALL_MODE:-}" in temp) tunnel_mode=1;; fixed) tunnel_mode=2;; *) read -r -p "Tunnel mode [1=temp, 2=fixed]: " tunnel_mode;; esac' \
 "$work/upstream.sh" > "$work/manager.sh"
# Keep built-in updater within this extension's boundary: reinstall instead.
sed -i '/^_update_script() {/a\    echo "Reinstall from zhangx16/Argo-Script to update this patched manager."; return 1' "$work/manager.sh"
bash -n "$work/manager.sh"
stamp=$(date -u +%Y%m%dT%H%M%SZ)-$$
backup="$BASE/backup-$stamp"
mkdir -m 700 "$backup"
for file in config.json argo_metadata.json clash.yaml argo-transport; do
 [ ! -f "/usr/local/etc/sing-box/$file" ] || cp -p "/usr/local/etc/sing-box/$file" "$backup/"
done
[ ! -f "$MANAGER" ] || cp -p "$MANAGER" "$backup/manager.sh"
printf '%s\n' "$transport" > "$work/transport"
install -m 600 "$work/transport" "$SETTINGS"
install -m 700 "$work/manager.sh" "$MANAGER"
printf '%s\n' "$UPSTREAM_REF" > "$BASE/upstream-ref"
echo "Transport=$transport; tunnel=$mode; backup=$backup"
echo 'The next prompts create a NEW node. Existing running tunnels are not restarted.'
ARGO_INSTALL_MODE=$mode bash "$MANAGER"

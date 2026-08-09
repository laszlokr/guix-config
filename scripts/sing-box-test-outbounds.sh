#!/bin/sh
# Test each sing-box outbound end-to-end.
#
# A listening TCP port proves only that something accepts connections.  This
# forces the selector to each outbound in turn, brings the tunnel up, and
# fetches an external address-echo service through it.  Getting the server's
# own IP back means the full path worked: TCP, TLS/REALITY handshake,
# credentials, and forwarding.
#
# Run as root (the TUN inbound needs it):
#
#     sudo scripts/sing-box-test-outbounds.sh
#
# Optionally pass the sing-box binary and config:
#
#     sudo scripts/sing-box-test-outbounds.sh /path/to/sing-box /etc/sing-box/config.json
#
# NOTE: this writes temporary copies of the config, which contain credentials.
# umask 077 keeps them private and they are removed on exit, including on
# interrupt.

set -eu

SING_BOX="${1:-}"
CONFIG="${2:-/etc/sing-box/config.json}"
EXPECTED_IP="${EXPECTED_IP:-}"

umask 077

if [ -z "$SING_BOX" ]; then
    if command -v sing-box >/dev/null 2>&1; then
        SING_BOX=$(command -v sing-box)
    else
        echo "sing-box not found on PATH; pass it as the first argument." >&2
        echo "e.g. sudo $0 \$(guix build sing-box)/bin/sing-box" >&2
        exit 1
    fi
fi

[ -r "$CONFIG" ] || { echo "cannot read $CONFIG" >&2; exit 1; }

TMPDIR_RUN=$(mktemp -d)
cleanup() {
    [ -n "${SB_PID:-}" ] && kill "$SB_PID" 2>/dev/null || true
    rm -rf "$TMPDIR_RUN"
}
trap cleanup EXIT INT TERM

# Every outbound that names a server -- i.e. the real proxies, not
# direct/block/selector/urltest.
TAGS=$(jq -r '.outbounds[]? | select(.server != null) | .tag' "$CONFIG")

printf '%-18s %-8s %s\n' OUTBOUND RESULT DETAIL
printf '%s\n' '---------------------------------------------------------------'

for tag in $TAGS; do
    cfg="$TMPDIR_RUN/$tag.json"
    jq --arg t "$tag" \
       '(.outbounds[] | select(.tag == "proxy")).default = $t' \
       "$CONFIG" > "$cfg"

    "$SING_BOX" run -c "$cfg" >"$TMPDIR_RUN/$tag.log" 2>&1 &
    SB_PID=$!

    # Give the TUN time to come up and routes to settle.
    sleep 4

    if ! kill -0 "$SB_PID" 2>/dev/null; then
        printf '%-18s %-8s %s\n' "$tag" FAIL "sing-box exited; see $TMPDIR_RUN/$tag.log"
        SB_PID=
        continue
    fi

    ip=$(curl -s --max-time 12 https://ifconfig.me || true)

    kill "$SB_PID" 2>/dev/null || true
    wait "$SB_PID" 2>/dev/null || true
    SB_PID=

    # Routes need a moment to revert before the next iteration.
    sleep 1

    if [ -z "$ip" ]; then
        detail=$(grep -m1 -i 'error' "$TMPDIR_RUN/$tag.log" 2>/dev/null || echo 'no response')
        printf '%-18s %-8s %s\n' "$tag" FAIL "$detail"
    elif [ -n "$EXPECTED_IP" ] && [ "$ip" != "$EXPECTED_IP" ]; then
        printf '%-18s %-8s %s\n' "$tag" LEAK "got $ip, expected $EXPECTED_IP"
    else
        printf '%-18s %-8s %s\n' "$tag" OK "exit IP $ip"
    fi
done

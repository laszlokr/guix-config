# Merge a server-issued sing-box client config into a system-wide TUN setup.
#
# Keeps every outbound from the source file EXACTLY as-is -- credentials,
# WebSocket transports, REALITY TLS settings and all -- and replaces only the
# parts that decide how traffic reaches those outbounds.
#
# Usage on box:
#
#     jq -f scripts/sing-box-merge.jq /tmp/singbox-client.json > /tmp/merged.json
#     sing-box check -c /tmp/merged.json
#     sudo install -m 0600 -o root -g root /tmp/merged.json /etc/sing-box/config.json
#     rm /tmp/singbox-client.json /tmp/merged.json
#
# What it changes:
#   inbounds  -> a single TUN inbound, so every host process is routed
#   dns       -> added; queries go through the proxy over TLS (source had none)
#   route     -> LAN/link-local stay direct; DNS is hijacked; everything else
#                goes to "proxy"
#   auto      -> urltest ordered trojan-reality first, vmess-tls second
#   proxy     -> selector defaults to "auto"
#
# Written for sing-box 1.13.x (rosenthal channel).  Uses the modern
# "action": "hijack-dns" route rule rather than a legacy dns-type outbound.

# Collect the literal IPv4 addresses of every outbound server, so they can be
# excluded from the tunnel.  Without this, auto_route sends the default route
# into tun0 and sing-box's own connection to the VPN server re-enters its own
# TUN -- a routing loop that surfaces as "connect: connection refused" even
# though the port is reachable directly.
#
# Derived from the config rather than hardcoded, so this script stays generic
# and no address is baked into the repo.  Outbounds using hostnames rather than
# IP literals yield nothing here and fall back to auto_detect_interface.
([.outbounds[]?
  | .server?
  | select(type == "string")
  | select(test("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$"))]
 | unique
 | map(. + "/32")) as $server_cidrs

# Route traffic into a TUN device instead of a local SOCKS/HTTP listener.
| .inbounds = [
  {
    "type": "tun",
    "tag": "tun-in",
    "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
    "mtu": 9000,
    "auto_route": true,
    "strict_route": true,
    "stack": "gvisor",
    "route_exclude_address": $server_cidrs
  }
]

# The source config has no DNS block at all, so queries would bypass the
# tunnel entirely.  Resolve over TLS through the proxy.
| .dns = {
    "servers": [
      {
        "tag": "dns-proxy",
        "type": "tls",
        "server": "1.1.1.1",
        "detour": "proxy"
      },
      {
        "tag": "dns-local",
        "type": "local"
      }
    ],
    "final": "dns-proxy",
    "strategy": "prefer_ipv4"
  }

| .route = {
    "rules": [
      # Protocol sniffing.  In sing-box 1.13 the inbound "sniff" field is gone
      # (deprecated in 1.11, removed in 1.13); it is a rule action now.  Without
      # this, the DNS rule below cannot match, because nothing identifies the
      # protocol of a connection.
      {
        "action": "sniff"
      },
      # Catch DNS before anything else and answer it via the dns block.
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      # Carve-outs: keep the local network reachable.  Without these you lose
      # SSH from other machines, local DNS, and anything else on the LAN.
      {
        "ip_cidr": [
          "127.0.0.0/8",
          "10.0.0.0/8",
          "172.16.0.0/12",
          "192.168.0.0/16",
          "169.254.0.0/16",
          "224.0.0.0/4",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outbound": "direct"
      },
      # The VPN server itself must never be routed through the tunnel.
      # Belt-and-braces alongside route_exclude_address on the inbound.
      {
        "ip_cidr": $server_cidrs,
        "outbound": "direct"
      },
      # Keep Guix substitutes direct so builds do not stall behind the tunnel.
      # Delete this rule if you want literally everything proxied.
      {
        "domain_suffix": [
          "bordeaux.guix.gnu.org",
          "substitutes.nonguix.org"
        ],
        "outbound": "direct"
      }
    ],
    "final": "proxy",
    # Which DNS server resolves domain names used by outbounds (your server's
    # hostname, urltest URLs).  Required since 1.12; omitting it is fatal in
    # 1.13 unless ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER is set.
    #
    # This MUST be the direct resolver, not dns-proxy: resolving the proxy
    # server's own hostname through the proxy is circular, and the tunnel
    # would never come up.
    "default_domain_resolver": {
      "server": "dns-local"
    },
    # Keeps traffic to the VPN server itself off the tunnel, which is what
    # prevents a routing loop.  Do not turn this off.
    "auto_detect_interface": true
  }

| .experimental.cache_file = {
    "enabled": true,
    "path": "/var/lib/sing-box/cache.db"
  }

# Trojan primary, vmess fallback, as requested.  vless-reality and hysteria2
# stay defined in the file and selectable by tag, just not in the auto rotation.
| (.outbounds[] | select(.tag == "auto")).outbounds
    = ["trojan-reality", "vmess-tls"]
| (.outbounds[] | select(.tag == "auto")).url
    = "https://www.gstatic.com/generate_204"
| (.outbounds[] | select(.tag == "auto")).interval = "3m"

| (.outbounds[] | select(.tag == "proxy")).default = "auto"

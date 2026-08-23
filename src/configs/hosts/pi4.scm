(define-module (configs hosts pi4)
  ;; nftables assumed to live here, consistent with this repo's earlier
  ;; (unverified, never build-tested) nftables work -- confirm on-device.
  #:use-module (gnu packages linux)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services dns)
  #:use-module (gnu services networking)
  #:use-module (gnu services shepherd)
  #:use-module (gnu services ssh)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system mapped-devices)
  #:use-module (guix gexp)
  #:use-module (rde features)
  #:use-module (rde features base)
  #:use-module (rde features system)
  #:use-module (rosenthal packages networking)
  #:use-module (rosenthal services networking))

;;; Raspberry Pi 4, planned role: DNS/monitoring/substitute-cache for the
;;; home LAN, and the home mesh's gateway -- the one host road devices
;;; (mintsystem, phone) dial into to reach the home LAN and .lan DNS while
;;; away.  See the plan this file was scaffolded from for the full design.
;;;
;;; STATUS: SCAFFOLDING, NOT BUILD-READY.  This host does not physically
;;; exist yet.  Every TODO below needs real on-device information this
;;; sandbox cannot produce -- no guix binary here, no real Pi4 hardware.
;;; Left out of configs.scm's dispatcher (see the comment there) until the
;;; base bring-up milestone below is done, the same way mintsystem.scm sits
;;; today.  Do not attempt to build this file as-is.
;;;
;;; Bring-up order, each a real milestone in its own right, not to be
;;; skipped or done out of order:
;;;   1. Plain Guix System boots at all -- no services beyond
;;;      hostname/networking/SSH.  Confirmed nontrivial: real reports of
;;;      firmware/image friction on Guix+RPi4 exist; budget real time.
;;;      Start from gnu/system/examples/raspberry-pi-64.tmpl.  Verify the
;;;      exact bootloader package on-device:
;;;          guix package -s u-boot-rpi
;;;      No bootloader-configuration is defined in this file at all yet --
;;;      deliberately.  This host's operating-system definition (still to
;;;      be written, alongside %pi4-features below, the way reform.scm has
;;;      both %reform-features and a full operating-system assembly) needs
;;;      one built from whatever that search actually returns.  Do not
;;;      guess a package name here; raspberry-pi-64.tmpl itself is the
;;;      better starting reference than anything invented for this file.
;;;   2. Once it boots, extract the running kernel's .config and check
;;;      CONFIG_IP_ADVANCED_ROUTER / CONFIG_IP_MULTIPLE_TABLES /
;;;      CONFIG_IPV6_MULTIPLE_TABLES -- the exact gap reform.scm's kernel
;;;      had (a Kconfig `if'-block gate, not SoC-specific, so there is no
;;;      structural reason a BCM2711 defconfig would differ from the A311D
;;;      one on this axis).  This host needs it arguably MORE than reform
;;;      did -- it is the router doing NAT/forwarding for other devices,
;;;      not just dialing one TUN outbound.  If unset, patch with
;;;      customize-linux exactly like reform.scm's %reform-kernel does; if
;;;      already set, %pi4-kernel below can stay a plain package reference.
;;;   3. Networking plumbing (IP forwarding + NAT/forwarding ruleset) below,
;;;      tested with a throwaway manual routing test BEFORE sing-box enters
;;;      the picture -- keep "is the Pi4 a working router" and "does
;;;      sing-box work" as separate, individually-debuggable failure
;;;      domains.  Conflating layers cost real time repeatedly the last
;;;      time this kind of debugging happened in this repo.
;;;   4. DNS (dnsmasq), tested from the Pi4's own LAN segment.
;;;   5. DDNS updater -- check on-device first:
;;;          guix package -s ddclient
;;;          guix system search ddclient
;;;      Guix's guix-patches bug#64669 shows ddclient was proposed for
;;;      removal in 2023 as unmaintained/broken; status on the currently
;;;      pinned Guix commit is unknown from this sandbox.  This file
;;;      defaults to the hand-rolled fallback (below) rather than assuming
;;;      ddclient-service-type exists -- switch to that service-type
;;;      instead if the on-device check confirms it is available; it would
;;;      be less code to maintain.
;;;   6. sing-box server (hysteria2 inbound), self-signed cert, ONE
;;;      throwaway test user first.  Manual home-router port-forward
;;;      (UDP, whatever port is chosen).  Acceptance test for the WHOLE
;;;      design: connect from a device on cellular data (genuinely off the
;;;      home LAN) and confirm both tunnel connectivity and .lan
;;;      resolution + LAN reachability work, before rolling client config
;;;      out to any other device.


;;; Storage layout -- TODO, entirely fictional until the real hardware is
;;; partitioned.  Fill in from `sudo blkid` on the actual installed disk,
;;; same as every other host file in this repo does.  microSD vs. USB-SSD
;;; boot media is itself an open decision for RPi4 reliability (microSD
;;; wear/corruption is a well-known RPi4 pain point) -- worth deciding
;;; before install, not after.

(define %pi4-root-uuid
  (uuid "TODO-fill-in-real-root-uuid"))

(define pi4-file-systems
  (list
   (file-system
    (mount-point "/")
    (device %pi4-root-uuid)
    (type "ext4"))))


;;; Kernel -- TODO, see bring-up step 2 above.  Placeholder package name;
;;; verify the actual RPi4-targeting kernel this Guix revision ships
;;; (`guix package -s linux-libre-arm64-generic`, or whatever the
;;; raspberry-pi-64.tmpl example actually specifies) before relying on
;;; this.  linux-libre-arm64-generic here is a guess at the closest
;;; existing name, not a confirmed one.

(define %pi4-kernel linux-libre-arm64-generic)


;;; IP forwarding
;;
;; Required for the Pi4 to route mesh-client traffic (arriving on the
;; sing-box TUN) onward to the real LAN.  Off by default on any Guix
;; System host.  sysctl-service-type/sysctl-configuration is the native
;; primitive for this -- VERIFY the exact field name on-device
;; (`guix show sysctl` / check (gnu services sysctl)) before building;
;; written here as best understanding, not confirmed against a live repl.

(define %pi4-sysctl-service
  (service sysctl-service-type
           (sysctl-configuration
            (settings
             '(("net.ipv4.ip_forward" . "1"))))))


;;; NAT / forwarding ruleset
;;
;; Distinct from the earlier client-side kill-switch design this repo's
;; history carries (box.scm, since superseded by rosenthal's native
;; sing-box-service-type) -- that solved "stop a client leaking outside
;; its own tunnel" (default-drop on output).  This is the opposite shape:
;; a forwarding ALLOW-list for a host acting as a router, plus masquerade
;; so mesh-client traffic appears on the LAN as coming from the Pi4
;; itself (the user's explicit choice: simpler, no home-router route
;; changes beyond the one port-forward already needed; the cost is that
;; box/the GPU machine see the Pi4's IP in their own logs, not the real
;; mesh client's).
;;
;; TODO: "tun0" is sing-box's TUN interface name by convention (confirmed
;; from this session's earlier client-side work) but VERIFY it matches
;; once the Pi4's actual sing-box server config exists -- a server-mode
;; TUN inbound could plausibly be named differently.  "end0"/"eth0" is a
;; guess at the Pi4's LAN interface name -- confirm with `ip link` on the
;; real hardware before relying on this ruleset.

(define %pi4-lan-interface "end0")     ; TODO verify against real hardware
(define %pi4-tun-interface "tun0")     ; TODO verify against real sing-box config
(define %pi4-lan-cidr "192.168.0.0/24")

(define %pi4-forwarding-ruleset
  (plain-file "pi4-forwarding.nft"
              (string-append "\
table inet pi4-forward {
  chain forward {
    type filter hook forward priority filter; policy drop;

    ct state established,related accept
    iif \"" %pi4-tun-interface "\" oif \"" %pi4-lan-interface "\" accept
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;

    iif \"" %pi4-tun-interface "\" oif \"" %pi4-lan-interface "\" \
ip daddr " %pi4-lan-cidr " masquerade
  }
}
")))

;; Loads the ruleset above at boot.  TODO: "/sbin/nft" is an assumption
;; carried over from earlier, never build-verified, nftables work in this
;; repo's history -- confirm with `guix build nftables` and check the
;; actual output path before relying on this.  respawn? #f: this is a
;; one-shot load, not a long-running process; nft -f exits once the
;; ruleset is applied, and there is nothing to keep running afterward.
(define (pi4-forwarding-shepherd-services config)
  (list
   (simple-service
    'pi4-nftables-forwarding
    shepherd-root-service-type
    (list
     (shepherd-service
      (provision '(pi4-nftables-forwarding))
      (requirement '(networking))
      (documentation "Loads the Pi4 forward/masquerade nftables ruleset.")
      (respawn? #f)
      (start
       #~(lambda _
           (zero? (system* #$(file-append nftables "/sbin/nft")
                           "-f" #$%pi4-forwarding-ruleset))))
      (stop
       #~(lambda _
           (system* #$(file-append nftables "/sbin/nft")
                     "delete" "table" "inet" "pi4-forward")
           #f)))))))

(define (feature-pi4-nftables-forwarding)
  (feature
   (name 'pi4-nftables-forwarding)
   (values '((pi4-nftables-forwarding . #t)))
   (system-services-getter pi4-forwarding-shepherd-services)))


;;; sing-box server (hysteria2 inbound)
;;
;; Real config, same secrets-outside-the-store discipline as
;; box.scm/reform.scm's client configs: a bare path string, created by
;; hand on the Pi4, never in git or the store.  This file only references
;; the path -- nothing here generates or manages the JSON's contents.
;;
;; TODO before this is real: self-signed cert generation, one throwaway
;; test user's hysteria2 password, the actual forwarded port (matching
;; whatever the home router's port-forward uses), a real DDNS hostname
;; once step 5 above lands.

(define %pi4-sing-box-config "/etc/sing-box/config.json")

(define %pi4-sing-box-service
  (service sing-box-service-type
           (sing-box-configuration
            (config-file %pi4-sing-box-config))))


;;; DNS (dnsmasq) for the .lan zone
;;
;; TODO: verify exact field names against this repo's pinned Guix version
;; -- specifically whether static .lan records belong in `addresses' or
;; via raw `extra-options' lines; this session's research could not pin
;; that down precisely from a sandboxed environment.  Placeholder record
;; below is illustrative shape only.

(define %pi4-dnsmasq-service
  (service dnsmasq-service-type
           (dnsmasq-configuration
            (no-resolv? #t)
            (servers '("1.1.1.1" "9.9.9.9"))
            ;; TODO verify this is the right field for static .lan entries
            (addresses (list "/box.lan/192.168.0.30"
                              "/gpu.lan/TODO-fill-in-once-that-host-exists")))))


;;; DDNS updater -- hand-rolled fallback
;;
;; Used unless bring-up step 5 confirms ddclient-service-type is actually
;; available on the pinned Guix commit, in which case prefer that instead
;; (less code to maintain).  Follows box.scm's feature-box-podman-compose
;; pattern exactly: a custom shepherd-service rather than an upstream
;; service-type, for exactly the same reason -- no good upstream option
;; confirmed to exist.
;;
;; Credentials read from a plain file OUTSIDE the store, same discipline
;; as %pi4-sing-box-config.  Provider is not yet chosen (open decision);
;; this assumes a simple authenticated HTTPS GET/PUT update endpoint,
;; which covers DuckDNS/Cloudflare/No-IP alike -- the actual URL template
;; is provider-specific and belongs in the credentials file, not here.

(define %pi4-ddns-credentials "/etc/ddns/credentials")

(define (pi4-ddns-shepherd-services config)
  (list
   (simple-service
    'pi4-ddns-update
    shepherd-root-service-type
    (list
     (shepherd-service
      (provision '(pi4-ddns-update))
      (requirement '(networking))
      (documentation
       "Hand-rolled DDNS updater -- see the comment above this definition \
in hosts/pi4.scm for why this is not ddclient-service-type.")
      (respawn? #t)
      (start
       #~(lambda _
           ;; TODO: this is a skeleton, not working code.  Fill in once a
           ;; DDNS provider is chosen: read the update URL/credentials
           ;; from %pi4-ddns-credentials (outside the store), curl it on
           ;; an interval.  Left unimplemented deliberately rather than
           ;; guessing a provider-specific URL shape.
           (error "pi4-ddns-update: not yet implemented -- see TODO in hosts/pi4.scm")))
      (stop #~(make-kill-destructor)))))))

(define (feature-pi4-ddns)
  (feature
   (name 'pi4-ddns)
   (values '((pi4-ddns . #t)))
   (system-services-getter pi4-ddns-shepherd-services)))


;;; Host-specific features

(define-public %pi4-features
  (list
   (feature-host-info
    #:host-name "pi4"
    #:timezone "Europe/Zurich")
   (feature-file-systems
    #:file-systems pi4-file-systems)
   (feature-kernel
    #:kernel %pi4-kernel)
   (feature-custom-services
    #:system-services
    (list
     (service openssh-service-type
              (openssh-configuration
               (password-authentication? #f)
               (permit-root-login 'prohibit-password)))
     %pi4-sysctl-service
     %pi4-dnsmasq-service
     %pi4-sing-box-service))
   (feature-pi4-nftables-forwarding)
   (feature-pi4-ddns)))

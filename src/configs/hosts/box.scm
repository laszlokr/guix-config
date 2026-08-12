(define-module (configs hosts box)
  #:use-module (gnu packages containers)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services shepherd)
  #:use-module (gnu services ssh)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system mapped-devices)
  #:use-module (guix gexp)
  #:use-module (rde features)
  #:use-module (rde features base)
  #:use-module (rde features system)
  #:use-module (rde features wm)
  #:use-module (rosenthal packages networking)
  #:use-module (rosenthal services networking))


;;; Host-specific file systems

(define box-mapped-devices
  (list
   (mapped-device
    (source (uuid "a018554d-cbc6-41cd-9457-112656cd5b60"))
    (target "cryptroot")
    (type luks-device-mapping))))

(define box-file-systems
  (list
   (file-system
    (mount-point "/boot/efi")
    (device (uuid "EBAA-2487" 'fat32))
    (type "vfat"))
   (file-system
    (mount-point "/")
    (device "/dev/mapper/cryptroot")
    (type "ext4")
    (dependencies box-mapped-devices))))


;;; Podman Compose Shepherd feature
;;
;; Starts each Podman Compose stack at boot via Shepherd.  Credentials
;; are read from the .env file next to the compose files.

(define %compose-dir "/home/laszlokr/guix-config/docker")

(define* (feature-box-podman-compose
          #:key (stacks '("automation")))
  "Start each named Podman Compose stack under docker/ at boot via Shepherd.
STACKS names the subdirectories to enable (out of odoo, nextcloud, ai,
automation, search) -- only the ones actually wanted, not all five, since
enabling this doesn't require running every stack that happens to have a
compose.yml on disk."
  (define (make-podman-compose-service name)
    (let ((compose-file (string-append %compose-dir "/" name "/compose.yml"))
          (env-file     (string-append %compose-dir "/.env"))
          (log-file     (string-append "/var/log/podman-" name ".log")))
      (shepherd-service
       (provision (list (string->symbol (string-append "podman-" name))))
       (requirement '(networking))
       (documentation (string-append "Podman Compose stack: " name))
       (respawn? #f)
       ;; This service's start/stop are a raw system* call, not the usual
       ;; make-forkexec-constructor -- Shepherd only auto-logs the latter,
       ;; so without an explicit redirect here podman-compose's actual
       ;; output goes nowhere Shepherd's own log (/var/log/shepherd.log)
       ;; or `herd status` ever shows, making failures here look silent
       ;; even though the underlying command isn't. Confirmed the hard
       ;; way: `herd start` reported plain failure with zero detail, while
       ;; the exact same command run manually via sudo printed a real
       ;; error every time.
       ;;
       ;; Shepherd (PID 1) also runs with a near-empty environment -- no
       ;; HOME in particular -- unlike an interactive `sudo` shell, where
       ;; root's HOME is inherited normally. podman/podman-compose may
       ;; depend on HOME to resolve their own state.
       ;;
       ;; redirect-port (tried first) failed: current-output-port here is
       ;; a string port internal to Shepherd's own logging, not an open
       ;; file port redirect-port can dup2 against. dup2 on raw fds from
       ;; open-fdes is the pattern gnu/services/base.scm itself uses for
       ;; exactly this (its greeter-sway-command) -- operates below
       ;; Guile's port abstraction entirely, so it doesn't matter what
       ;; current-output-port is bound to.
       ;;
       ;; podman-compose is invoked here via its exact store path
       ;; (file-append), bypassing PATH entirely -- but podman-compose's
       ;; own code shells out to the separate `podman` binary by bare
       ;; name, which does need PATH. podman's own package wraps its PATH
       ;; with catatonit/conmon/crun/iptables/etc (see the podman package
       ;; definition's wrap-podman phase), but nothing gives Shepherd's
       ;; own near-empty PATH any way to find podman itself in the first
       ;; place. Confirmed missing directly: even a bare `podman-compose`
       ;; lookup fails under Shepherd-style minimal PATH.
       (start #~(lambda _
                  (setenv "HOME" "/root")
                  (setenv "PATH"
                          (string-append #$(file-append podman "/bin") ":"
                                         (or (getenv "PATH") "")))
                  (dup2 (open-fdes #$log-file
                                    (logior O_CREAT O_WRONLY O_APPEND) #o640)
                        1)
                  (dup2 1 2)
                  (zero? (system*
                          #$(file-append podman-compose "/bin/podman-compose")
                          "-f" #$compose-file
                          "--env-file" #$env-file
                          "up" "-d"))))
       (stop #~(lambda _
                 (setenv "HOME" "/root")
                 (setenv "PATH"
                         (string-append #$(file-append podman "/bin") ":"
                                        (or (getenv "PATH") "")))
                 (dup2 (open-fdes #$log-file
                                   (logior O_CREAT O_WRONLY O_APPEND) #o640)
                       1)
                 (dup2 1 2)
                 (system*
                  #$(file-append podman-compose "/bin/podman-compose")
                  "-f" #$compose-file
                  "--env-file" #$env-file
                  "down")
                 #f)))))

  (define (podman-compose-system-services config)
    (list
     (simple-service 'podman-compose-stacks
                     shepherd-root-service-type
                     (map make-podman-compose-service stacks))))

  (feature
   (name 'box-podman-compose)
   (values '((box-podman-compose . #t)))
   (system-services-getter podman-compose-system-services)))


;;; Host-specific features

(define-public %box-features
  (list
   (feature-host-info
    #:host-name "box"
    #:timezone "Europe/Zurich")
   (feature-file-systems
    #:file-systems box-file-systems
    #:mapped-devices box-mapped-devices)
   (feature-custom-services
    #:system-services
    (list
     (service openssh-service-type
              (openssh-configuration
               (password-authentication? #f)
               (permit-root-login 'prohibit-password)))
     ;; Serves substitutes to `reform' (see doc/reform-build-box.md) so its
     ;; guix pull/system reconfigure mostly download instead of building
     ;; under QEMU emulation.  Port 3000 -- guix publish's usual example
     ;; port, and what earlier docs here assumed -- is already bound to
     ;; Open WebUI (docker/ai/compose.yml, 127.0.0.1:3000:8080).  That's a
     ;; loopback-only bind, but this service needs host "0.0.0.0" to be
     ;; reachable from the Reform at all, and 0.0.0.0:N and 127.0.0.1:N
     ;; can't both be bound -- so this needs its own, actually-free port.
     ;; Keep this in sync with REFORM_SUBSTITUTE_URLS in the Makefile and
     ;; the box.lan references in doc/reform-build-box.md and
     ;; doc/reform-install.md if it ever moves again.
     (service guix-publish-service-type
              (guix-publish-configuration
               (host "0.0.0.0")
               (port 3001)
               (compression '(("zstd" 3)))
               (advertise? #f)
               (ttl (* 30 24 3600))))
     ;; SECURITY: the real config holds a trojan password and a vmess UUID.
     ;; Anything in the store is world-readable, so it is NOT generated from
     ;; this file -- config-file is a bare path string (rosenthal's
     ;; file-object? accepts one alongside actual file-like objects for
     ;; exactly this reason), created by hand at
     ;;
     ;;     /etc/sing-box/config.json      root:root, chmod 0600
     ;;
     ;; from the credential-free template at files/sing-box/config.template.json.
     ;; Same setup as reform; see hosts/reform.scm.
     (service sing-box-service-type
              (sing-box-configuration
               (config-file "/etc/sing-box/config.json")))))
   ;; Only automation (n8n + gotify) runs unattended for now -- the other
   ;; four stacks under docker/ (odoo, nextcloud, ai, search) stay off
   ;; until there's an actual need for them; add their names to #:stacks
   ;; here when that changes instead of turning all five on at once.
   (feature-box-podman-compose #:stacks '("automation"))
   (feature-kanshi
    #:extra-config
    ;; The triple profile matches the usual desk setup: 4K landscape in the
    ;; middle, a portrait panel either side.  Without it none of the profiles
    ;; matched a three-output configuration, so kanshi stayed idle and DP-2
    ;; was left wherever sway defaulted it.  Geometry mirrors
    ;; sway-extra-config-service in users/laszlokr.scm -- keep the two in sync.
    `((profile single ((output HDMI-A-1 enable)))
      (profile dual ((output HDMI-A-1 enable)
                     (output HDMI-A-2 enable)))
      (profile triple ((output HDMI-A-1 enable mode 1920x1080
                               position 0,120 transform 90)
                       (output HDMI-A-2 enable mode 3840x2160
                               position 1080,0)
                       (output DP-2 enable mode 1920x1080
                               position 4920,120 transform 270)))))))

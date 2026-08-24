(define-module (configs hosts box)
  #:use-module (gnu bootloader)
  #:use-module (gnu bootloader grub)
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


;;; Bootloader
;;
;; box's root is LUKS-encrypted, and /boot lives on it -- so the GRUB EFI
;; binary must carry the cryptodisk modules or it cannot read
;; /boot/grub/grub.cfg at all.  Stock grub-efi-bootloader sets
;; GRUB_ENABLE_CRYPTODISK=y but passes no --modules, and on this machine
;; that was not enough: a reconfigure that let guix install the bootloader
;; left it at a `grub rescue' prompt, recovered only with USB media and a
;; manual grub-install naming the modules explicitly.
;;
;; The workaround until now was --no-bootloader on box/system/reconfigure
;; plus a manual repair step.  That has a cost beyond the extra command:
;; guix's install-bootloader does two things -- install-boot-config, which
;; writes grub.cfg and therefore the *menu*, and the installer, which writes
;; the binary.  --no-bootloader skips both, so the menu silently stopped
;; tracking reality; between May and August box booted a three-month-old
;; generation by default while running a current one.  See
;; doc/box-bootloader.md.
;;
;; This bootloader closes that off properly: same installer as upstream's
;; make-grub-efi-installer, with --modules added, so guix's own bootloader
;; step produces a bootable binary and --no-bootloader is no longer needed.
;;
;; Deliberately NOT --removable, unlike the grub-efi-removable-bootloader
;; rde defaults to.  The proven-working install on this machine -- the one
;; that recovered it from the rescue prompt, and what it boots today -- is
;; --bootloader-id=Guix without --removable, i.e. EFI/Guix plus an NVRAM
;; entry rather than EFI/BOOT/BOOTX64.EFI.  Matching the declared bootloader
;; type would arguably be tidier; this matches what is known to boot.

(define %box-grub-modules
  ;; Enough to open the LUKS2 root and read /boot/grub from it.  Same list
  ;; used by the manual recovery command in the Makefile's
  ;; box/system/install-bootloader target; keep the two in step.
  "cryptodisk luks2 gcry_rijndael gcry_sha256 ext2 part_gpt")

(define install-grub-efi/cryptodisk
  ;; Upstream make-grub-efi-installer (gnu/bootloader/grub.scm) verbatim,
  ;; minus the efi32?/removable? cases box does not use, plus --modules.
  ;; invoke/quiet comes from (guix build utils), which guix's
  ;; install-bootloader-program already imports around this gexp.
  #~(lambda (bootloader efi-dir mount-point)
      ;; Nothing useful to do when generating a disk image.
      (when efi-dir
        (let ((grub-install (string-append bootloader "/sbin/grub-install"))
              (install-dir (string-append mount-point "/boot"))
              ;; When installing, efi-dir is commonly mounted below
              ;; mount-point rather than at /boot/efi.
              (target-esp (if (file-exists? (string-append mount-point efi-dir))
                              (string-append mount-point efi-dir)
                              efi-dir)))
          (setenv "GRUB_ENABLE_CRYPTODISK" "y")
          (invoke/quiet grub-install "--bootloader-id=Guix"
                        "--boot-directory" install-dir
                        "--efi-directory" target-esp
                        (string-append "--modules=" #$%box-grub-modules))))))

(define box-grub-bootloader
  (bootloader
   (inherit grub-efi-bootloader)
   (name 'grub-efi-cryptodisk)
   (installer install-grub-efi/cryptodisk)))

(define box-bootloader-configuration
  (bootloader-configuration
   (bootloader box-grub-bootloader)
   (targets (list "/boot/efi"))))


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
       ;; `podman-compose up -d' starts containers and exits -- it is not
       ;; a long-running daemon, so this is a one-shot service: Shepherd
       ;; treats a zero exit as "started" rather than waiting on a process
       ;; that will never stay up.
       (one-shot? #t)
       ;; make-forkexec-constructor rather than a hand-rolled system* in a
       ;; custom lambda.  The hand-rolled version was tried first and cost
       ;; several debugging rounds, because Shepherd only wires up logging
       ;; and environment for the forkexec path:
       ;;
       ;;  * With a bare `system*', podman-compose's stdout/stderr went
       ;;    nowhere `herd status' or /var/log/shepherd.log ever showed --
       ;;    every failure looked silent even though running the identical
       ;;    command by hand printed a real error each time.  #:log-file
       ;;    gets this for free and Shepherd manages the file itself.
       ;;  * Redirecting by hand was its own trap: `redirect-port' fails
       ;;    here ("expecting open file port") because current-output-port
       ;;    inside a start gexp is a string port internal to Shepherd's
       ;;    logging, not a file port.
       ;;  * Shepherd (PID 1) runs with a near-empty environment: no HOME,
       ;;    and a PATH that cannot find `podman'.  That matters even
       ;;    though podman-compose itself is named by absolute store path
       ;;    below, because podman-compose shells out to `podman' by bare
       ;;    name.  #:environment-variables sets both explicitly.
       (start #~(make-forkexec-constructor
                 (list #$(file-append podman-compose "/bin/podman-compose")
                       "-f" #$compose-file
                       "--env-file" #$env-file
                       "up" "-d")
                 #:log-file #$log-file
                 #:environment-variables
                 (list (string-append "PATH=" #$(file-append podman "/bin")
                                      ":/run/current-system/profile/bin")
                       "HOME=/root")))
       (stop #~(make-forkexec-constructor
                (list #$(file-append podman-compose "/bin/podman-compose")
                      "-f" #$compose-file
                      "--env-file" #$env-file
                      "down")
                #:log-file #$log-file
                #:environment-variables
                (list (string-append "PATH=" #$(file-append podman "/bin")
                                     ":/run/current-system/profile/bin")
                      "HOME=/root"))))))

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
   (feature-bootloader
    #:bootloader-configuration box-bootloader-configuration)
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
     ;;
     ;; If this service crash-loops with
     ;;
     ;;     FATAL start service: initialize cache-file: timeout
     ;;
     ;; the cause is almost certainly a second sing-box already running --
     ;; typically one started by hand before the service existed.  Its cache
     ;; database (/var/lib/sing-box/cache.db) is file-locked, so the service's
     ;; instance waits ~9s for the lock, gives up, exits 1, and gets
     ;; respawned forever.  The message names the symptom, not the conflict.
     ;; Check with `pgrep -a sing-box'; if there are two, stop the service,
     ;; kill the manual instance, then start the service again.  Note this
     ;; drops the tunnel, so do not do it over an SSH session routed through
     ;; the VPN.
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

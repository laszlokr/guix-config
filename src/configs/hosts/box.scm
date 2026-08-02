(define-module (configs hosts box)
  #:use-module (gnu packages containers)
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (gnu services ssh)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system mapped-devices)
  #:use-module (guix gexp)
  #:use-module (rde features)
  #:use-module (rde features base)
  #:use-module (rde features system)
  #:use-module (rde features wm))


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

(define (feature-box-podman-compose)
  (define (make-podman-compose-service name)
    (let ((compose-file (string-append %compose-dir "/" name "/compose.yml"))
          (env-file     (string-append %compose-dir "/.env")))
      (shepherd-service
       (provision (list (string->symbol (string-append "podman-" name))))
       (requirement '(networking))
       (documentation (string-append "Podman Compose stack: " name))
       (respawn? #f)
       (start #~(lambda _
                  (zero? (system*
                          #$(file-append podman-compose "/bin/podman-compose")
                          "-f" #$compose-file
                          "--env-file" #$env-file
                          "up" "-d"))))
       (stop #~(lambda _
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
                     (map make-podman-compose-service
                          (list "odoo" "nextcloud" "ai" "automation" "search")))))

  (feature
   (name 'box-podman-compose)
   (values '((box-podman-compose . #t)))
   (system-services-getter podman-compose-system-services)))


;;; sing-box VPN feature
;;
;; System-wide transparent proxy via a TUN interface: every host process,
;; including podman containers (their egress goes through the host routing
;; table), is routed through the tunnel.
;;
;; SECURITY: the configuration holds a trojan password and a vmess UUID.
;; Anything Guix puts in the store is WORLD-READABLE, so the config is NOT
;; generated from this file.  It lives outside the store at
;;
;;     /etc/sing-box/config.json      root:root, chmod 0600
;;
;; created by hand on box from the committed, credential-free template at
;; files/sing-box/config.template.json.  This service only references the
;; path.  Never commit the real config.
;;
;; The package comes from the rosenthal channel:
;;   (rosenthal packages networking) -> sing-box 1.13.12, built with
;;   with_gvisor, which is what makes the TUN inbound work.

(define %sing-box-config "/etc/sing-box/config.json")

(define (feature-box-sing-box)
  (define (sing-box-shepherd-services config)
    (list
     (simple-service
      'sing-box
      shepherd-root-service-type
      (list
       (shepherd-service
        (provision '(sing-box))
        (requirement '(networking))
        (documentation "sing-box transparent proxy (TUN, system-wide).")
        (respawn? #t)
        (start
         #~(make-forkexec-constructor
            (list #$(file-append (@ (rosenthal packages networking) sing-box)
                                 "/bin/sing-box")
                  "run" "-c" #$%sing-box-config)
            #:log-file "/var/log/sing-box.log"))
        (stop #~(make-kill-destructor)))))))

  (feature
   (name 'box-sing-box)
   (values '((box-sing-box . #t)))
   (system-services-getter sing-box-shepherd-services)))


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
               (permit-root-login 'prohibit-password)))))
   ;; Compose stacks are started by hand while the system is up, so the
   ;; boot-time Shepherd services are not wired in.  feature-box-podman-compose
   ;; above is kept for when they should run unattended again.
   ;; (feature-box-podman-compose)
   (feature-box-sing-box)
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
                               position 0,120 transform 270)
                       (output HDMI-A-2 enable mode 3840x2160
                               position 1080,0)
                       (output DP-2 enable mode 1920x1080
                               position 4920,120 transform 90)))))))

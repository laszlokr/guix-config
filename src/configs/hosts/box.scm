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
               (ttl (* 30 24 3600))))))
   (feature-box-podman-compose)
   (feature-kanshi
    #:extra-config
    `((profile single ((output HDMI-A-1 enable)))
      (profile dual ((output HDMI-A-1 enable)
                     (output HDMI-A-2 enable)))))))

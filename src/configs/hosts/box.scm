(define-module (configs hosts box)
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


;;; Docker Compose Shepherd feature
;;
;; Starts each Docker Compose stack at boot via Shepherd.  Credentials
;; are read from the .env file next to the compose files.  dockerd is
;; provided by feature-docker in laszlokr.scm.

(define %docker-dir "/home/laszlokr/guix-config/docker")

(define (feature-box-docker-compose)
  (define (make-docker-compose-service name)
    (let ((project-dir (string-append %docker-dir "/" name))
          (env-file    (string-append %docker-dir "/.env")))
      (shepherd-service
       (provision (list (string->symbol (string-append "docker-" name))))
       (requirement '(dockerd networking))
       (documentation (string-append "Docker Compose stack: " name))
       (respawn? #f)
       (start #~(lambda _
                  (zero? (system* "/run/current-system/profile/bin/docker"
                                  "compose"
                                  "--project-directory" #$project-dir
                                  "--env-file" #$env-file
                                  "up" "--detach" "--wait"))))
       (stop #~(lambda _
                 (system* "/run/current-system/profile/bin/docker"
                          "compose"
                          "--project-directory" #$project-dir
                          "down")
                 #f)))))

  (define (docker-compose-system-services config)
    (list
     (simple-service 'docker-compose-stacks
                     shepherd-root-service-type
                     (map make-docker-compose-service
                          (list "odoo" "nextcloud" "ai" "automation" "search")))))

  (feature
   (name 'box-docker-compose)
   (values '((box-docker-compose . #t)))
   (system-services-getter docker-compose-system-services)))


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
   (feature-box-docker-compose)
   (feature-kanshi
    #:extra-config
    `((profile single ((output HDMI-A-1 enable)))
      (profile dual ((output HDMI-A-1 enable)
                     (output HDMI-A-2 enable)))))))

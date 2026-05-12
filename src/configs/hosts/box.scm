(define-module (configs hosts box)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services ssh)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system mapped-devices)
  #:use-module (rde features)
  #:use-module (rde features base)
  #:use-module (rde features system)
  #:use-module (rde features wm))


;;; Host-specific features and services

;; Define the mapped device for encrypted root
(define box-mapped-devices
  (list
   (mapped-device
    (source (uuid "a018554d-cbc6-41cd-9457-112656cd5b60"))
    (target "cryptroot")
    (type luks-device-mapping))))

;; Define file systems, including the encrypted root
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

;; Custom system services for `box`
(define box-custom-services
  (list
   (service openssh-service-type
            (openssh-configuration
             (password-authentication? #f)
             (permit-root-login 'prohibit-password)))))


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
    #:system-services box-custom-services)
   (feature-kanshi
    #:extra-config
    `((profile laptop ((output eDP-1 enable)))
      (profile docked ((output eDP-1 enable)
                       (output DP-2 scale 2)))))
   (feature-hidpi)))

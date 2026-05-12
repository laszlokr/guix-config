(define-module (configs hosts mintsystem)
  #:use-module (gnu services)
  #:use-module (gnu services ssh)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system mapped-devices)
  #:use-module (rde features)
  #:use-module (rde features base)
  #:use-module (rde features system)
  #:use-module (rde features wm))


;;; Host-specific features and services

;; TODO: Fill in UUID from `sudo blkid` for the encrypted root device
(define mintsystem-mapped-devices
  (list
   (mapped-device
    (source (uuid "TODO-fill-in-luks-uuid"))
    (target "cryptroot")
    (type luks-device-mapping))))

;; TODO: Fill in EFI partition UUID from `sudo blkid`
(define mintsystem-file-systems
  (list
   (file-system
    (mount-point "/boot/efi")
    (device (uuid "TODO-fill-in-efi-uuid" 'fat32))
    (type "vfat"))
   (file-system
    (mount-point "/")
    (device "/dev/mapper/cryptroot")
    (type "ext4")
    (dependencies mintsystem-mapped-devices))))

(define mintsystem-custom-services
  (list
   (service openssh-service-type
            (openssh-configuration
             (password-authentication? #f)
             (permit-root-login 'prohibit-password)))))


;;; Host-specific features

(define-public %mintsystem-features
  (list
   (feature-host-info
    #:host-name "mintsystem"
    #:timezone "Europe/Zurich")
   (feature-file-systems
    #:file-systems mintsystem-file-systems
    #:mapped-devices mintsystem-mapped-devices)
   (feature-custom-services
    #:system-services mintsystem-custom-services)
   (feature-kanshi
    #:extra-config
    `((profile laptop ((output eDP-1 enable)))
      (profile docked ((output eDP-1 enable)
                       (output DP-1 enable)))))
   (feature-hidpi)))

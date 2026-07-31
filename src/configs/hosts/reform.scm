(define-module (configs hosts reform)
  #:use-module (gnu bootloader)
  #:use-module (gnu bootloader extlinux)
  #:use-module (gnu services)
  #:use-module (gnu services ssh)
  #:use-module (gnu system file-systems)
  #:use-module (rde features)
  #:use-module (rde features base)
  #:use-module (rde features system)
  ;; Kernel with the full-size Reform BPI-CM4 device tree.  Provided by
  ;; lykso's out-of-tree checkout, NOT by a channel -- see "Kernel" below.
  #:use-module (mnt-reform a311d))


;;; Hardware
;;
;; MNT Reform (full-size chassis) with a Banana Pi CM4 module (Amlogic A311D,
;; aarch64).  Target: full Guix System on NVMe, replacing MNT's Debian.


;;; Kernel
;;
;; Upstream guix ships linux-libre-arm64-mnt-reform, but its device tree list
;; contains only meson-g12b-bananapi-cm4-mnt-pocket-reform.dts for Amlogic --
;; i.e. the *Pocket* Reform.  There is no full-size BPI-CM4 device tree
;; upstream, so that kernel cannot boot this machine.
;;
;; lykso's tree carries meson-g12b-bananapi-cm4-mnt-reform2.dts, which is the
;; one this chassis needs, and exports:
;;
;;     (define-public linux-mnt-reform-a311d-6.6 (make-linux-kernel "0x1000000"))
;;
;; from module (mnt-reform a311d).
;;
;; NOTE: lykso's repo declares (directory ".guix/modules") in .guix-channel,
;; but that path does not exist in the repository, so adding it to channels.scm
;; would yield a channel exposing no modules.  It must be used as a local
;; checkout instead:
;;
;;     git clone https://codeberg.org/lykso/mnt-reform-nonguix
;;     guix system build -L /path/to/mnt-reform-nonguix ...
;;
;; The channel also publishes no channel introduction, so it cannot be
;; authenticated even once the module path is fixed.  Pin a reviewed commit.
;; Reviewed at: 3b78db7a2b32f96ecdf8d74a189b6ab386615757 (2025-04-24).
;;
;; This kernel comes from the nonguix side and is not linux-libre.

(define reform-kernel linux-mnt-reform-a311d-6.6)

;; Serial console matches lykso's A311D configuration.
(define reform-kernel-arguments
  (list "console=ttyAML0,115200"))

;; Root lives on NVMe, so the NVMe driver must be in the initrd or the root
;; filesystem cannot be found at boot.  lykso's A311D config is validated for
;; SD-card boot only; NVMe root is the part of this setup that is new.
(define reform-initrd-modules
  (list "nvme" "nvme-core"))


;;; File systems
;;
;; TODO: Replace both UUIDs with real values from the running system:
;;
;;     sudo blkid /dev/nvme0n1p1   # -> boot (ext4)
;;     sudo blkid /dev/nvme0n1p2   # -> root (ext4)
;;
;; Partition layout assumed here:
;;   /dev/nvme0n1p1  ext4  /boot   (holds extlinux.conf, kernel, dtb)
;;   /dev/nvme0n1p2  ext4  /

(define reform-file-systems
  (list
   (file-system
     (mount-point "/boot")
     (device (uuid "TODO-FILL-IN-NVME-BOOT-UUID" 'ext4))
     (type "ext4"))
   (file-system
     (mount-point "/")
     (device (uuid "TODO-FILL-IN-NVME-ROOT-UUID" 'ext4))
     (type "ext4"))))


;;; Bootloader
;;
;; extlinux, NOT u-boot-bootloader.  U-Boot already lives in the module's
;; firmware and Guix must never write to it.  extlinux-bootloader only writes
;; an extlinux.conf (plus kernel/initrd) into the target directory; it does not
;; touch any raw boot sectors.
;;
;; This deliberately diverges from lykso's a311d.scm, which builds
;; u-boot-a311d-reform2 and installs it to /dev/mmcblk1 for a fresh SD image.
;; That path is for bootstrapping a blank card; it is not wanted here.
;;
;; Targets point at the NVMe boot mount, never the SD card.

(define reform-bootloader
  (bootloader-configuration
   (bootloader extlinux-bootloader)
   (targets (list "/boot"))))


;;; Host features

(define-public %reform-features
  (list
   (feature-host-info
    #:host-name "reform"
    #:timezone "Europe/Zurich")
   (feature-file-systems
    #:file-systems reform-file-systems)
   (feature-kernel
    #:kernel reform-kernel
    #:kernel-arguments reform-kernel-arguments
    #:initrd-modules reform-initrd-modules)
   (feature-bootloader
    #:bootloader-configuration reform-bootloader)
   (feature-custom-services
    #:system-services
    (list
     (service openssh-service-type
              (openssh-configuration
               (password-authentication? #f)
               (permit-root-login 'prohibit-password)))))))

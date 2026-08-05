(define-module (configs hosts reform)
  #:use-module (gnu bootloader)
  #:use-module (gnu bootloader extlinux)
  #:use-module (gnu packages firmware)
  #:use-module (gnu packages linux)
  #:use-module (gnu services)
  #:use-module (gnu services ssh)
  #:use-module (gnu services virtualization)
  #:use-module (gnu system)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system linux-initrd)
  #:use-module (srfi srfi-1)
  #:use-module (rde features)
  #:use-module (rde features base)
  #:use-module (rde features system))

;;; MNT Reform with a Banana Pi CM4 module (Amlogic A311D, aarch64).
;;;
;;; Root lives on the NVMe SSD.  The SD card keeps MNT's Debian as a
;;; fallback and is never touched by Guix.
;;;
;;; See doc/reform-install.md for the partitioning and `guix system init'
;;; procedure this host definition is meant to be installed with.


;;; Bootloader
;;
;; U-Boot is flashed on the CM4 module itself.  Guix must never write to
;; it, so this host installs *no* bootloader code at all -- it only writes
;; /boot/extlinux/extlinux.conf, which the module's U-Boot reads through
;; its distro-boot ("bootcmd_nvme0" -> sysboot) path.
;;
;; Upstream's plain `extlinux-bootloader' is NOT usable here, for two
;; independent reasons:
;;
;;   1. Its `package' field is `syslinux', whose supported-systems are
;;      i686-linux and x86_64-linux only (the Makefile targets nasm/x86).
;;      It cannot be built for aarch64-linux at all.
;;
;;   2. Its installer (`install-extlinux' in (gnu bootloader extlinux))
;;      runs syslinux's `extlinux --install' and then writes syslinux's
;;      MBR boot block onto the target device at byte offset 440 -- i.e.
;;      exactly the "write a bootloader to the disk" behaviour we must
;;      avoid.
;;
;; So we inherit the extlinux *configuration generator* (that is the part
;; we want: it emits the LABEL/KERNEL/FDTDIR/INITRD/APPEND file U-Boot
;; understands) and drop the package and the installer.  With both
;; `installer' and `disk-image-installer' set to #f, guix's
;; install-bootloader-program skips the install step entirely and only
;; runs `install-boot-config', which writes the text file below TARGET.
;;
;; Note: upstream's generic `u-boot-bootloader' is defined exactly this
;; way -- (inherit extlinux-bootloader) with (package #f) (installer #f)
;; -- so it behaves identically and also does not write U-Boot anywhere
;; during `guix system init'.  The definition is spelled out here instead
;; so that the intent ("extlinux.conf only, never touch the module's
;; U-Boot") is visible at the call site rather than hidden behind a name
;; that reads like it flashes U-Boot.
(define reform-extlinux-bootloader
  (bootloader
   (inherit extlinux-bootloader)
   (name 'extlinux-no-install)
   (package #f)
   (installer #f)))

(define reform-bootloader-configuration
  (bootloader-configuration
   (bootloader reform-extlinux-bootloader)
   ;; Informational only, since there is no installer to run: it is the
   ;; mount point under which extlinux.conf is written.  It must be on
   ;; the NVMe, never the SD card.
   ;;
   ;; IMPORTANT: /boot must live on the root file system, not on a
   ;; separate partition.  extlinux.conf references the kernel and initrd
   ;; by absolute /gnu/store/... path, and U-Boot resolves those paths on
   ;; the same partition it loaded extlinux.conf from.  A separate /boot
   ;; partition would make U-Boot look for /gnu/store there and fail.
   (targets (list "/boot"))
   ;; Emits "FDTDIR <kernel>/lib/dtbs" so U-Boot picks the device tree
   ;; named by its own $fdtfile -- meson-g12b-bananapi-cm4-mnt-reform2.dtb
   ;; on this module.  (#t is the default; stated explicitly because it is
   ;; load-bearing on this machine.)
   (device-tree-support? #t)
   (timeout 3)))


;;; File systems
;;
;; TODO(laszlo): replace the placeholder UUIDs below with the real ones,
;; read on the running Debian *after* formatting the NVMe:
;;
;;     sudo blkid /dev/nvme0n1p1
;;
;; They are syntactically valid so that the configuration still evaluates
;; and builds (an unparseable placeholder would break `guix system build'
;; and defeat the point of checking the config).  Forgetting to replace
;; them is caught: `guix system init', run as root, calls
;; check-file-system-availability and refuses to install when the UUID
;; does not resolve to a real device.
;;
;; Format the root file system with U-Boot-compatible options; see
;; doc/reform-install.md.

(define %reform-root-uuid
  ;; TODO(laszlo): PLACEHOLDER -- real UUID of /dev/nvme0n1p1
  (uuid "00000000-0000-0000-0000-000000000001"))

(define reform-file-systems
  (list
   (file-system
    (mount-point "/")
    (device %reform-root-uuid)
    (type "ext4"))))


;;; Kernel
;;
;; `linux-libre-arm64-mnt-reform' is upstream in (gnu packages linux); it
;; is an alias for the current default variant, which resolves to 7.0.14
;; at the pinned guix commit.  It carries MNT's device trees and patches,
;; including the meson-g12b-bananapi-cm4-mnt-reform2 ones this A311D
;; module needs.  Pin a specific variant -- linux-libre-arm64-mnt-reform-7.1
;; (7.1.3 at this commit), -6.19, -6.18, -6.12 also exist -- if a channel
;; update moves the alias.  Note `guix show linux-libre-arm64-mnt-reform'
;; reports 7.1.3: it matches by package *name*, of which several variants
;; share one, and shows the newest.  The variable is the 7.0 one.
;;
;; linux-firmware (nonguix) is kept from the shared feature set: the
;; CM4's Wi-Fi/Bluetooth is a Broadcom SDIO part that needs brcmfmac
;; blobs.  The kernel itself is the libre one; only the firmware is
;; nonfree.

(define %reform-initrd-modules
  ;; %base-initrd-modules expands to (default-initrd-modules) evaluated
  ;; against (%current-system), and rde's feature-kernel takes it as a
  ;; keyword default -- i.e. on the *build* machine.  Building this host
  ;; from x86_64 therefore drags in three modules that exist only in an
  ;; x86 kernel, and the initrd build would fail looking for them.
  ;; (Verified: without this filter the resulting operating-system carries
  ;; "isci"; with it the list is 24 -> 21 modules.)  Everything else in the
  ;; base list -- including "nvme", needed to find the root device -- is
  ;; architecture-neutral.
  (remove (lambda (module)
            (member module '("pata_acpi" "pata_atiixp" "isci")))
          %base-initrd-modules))


;;; Host-specific services

(define reform-custom-services
  (list
   (service openssh-service-type
            (openssh-configuration
             (password-authentication? #f)
             (permit-root-login 'prohibit-password)))))


;;; Architecture fixup applied after the features are folded
;;
;; rde's feature-qemu instantiates libvirt-service-type with its default
;; configuration, whose `firmwares' field is (list ovmf-x86-64) -- x86 UEFI
;; firmware for guest VMs.  On aarch64 that package does not build: EDK2's
;; X64 modules end up compiled by the native aarch64 gcc, which rejects the
;; x86 flags EDK2 passes ("gcc: error: unrecognized command-line option
;; '-m64'", likewise -mno-red-zone, -mno-mmx, -maccumulate-outgoing-args),
;; and no substitute server has an aarch64 build of it.  Left alone it makes
;; the entire system closure unbuildable.
;;
;; feature-qemu does not expose the libvirt configuration, so swap the
;; firmware in afterwards.  ovmf-aarch64 is upstream in (gnu packages
;; firmware) and is fully substitutable for aarch64 (~1 MiB) -- and it is
;; the firmware this machine's guests would actually want anyway.

(define-public (reform-operating-system config)
  "Return the <operating-system> for CONFIG, an <rde-config>, with the
architecture fixups this host needs."
  (let ((os (rde-config-operating-system config)))
    (operating-system
     (inherit os)
     (services
      (modify-services (operating-system-user-services os)
        (libvirt-service-type
         libvirt-config =>
         (libvirt-configuration
          (inherit libvirt-config)
          (firmwares (list ovmf-aarch64)))))))))


;;; Host-specific features
;;
;; Everything else -- the whole rde feature set -- comes from
;; %laszlokr-features.  configs.scm drops exactly one of its features for
;; this host: `kernel', which pins the x86 nonguix kernel (and rde throws on
;; duplicate feature values).

(define-public %reform-features
  (list
   (feature-host-info
    #:host-name "reform"
    #:timezone "Europe/Zurich")
   (feature-bootloader
    #:bootloader-configuration reform-bootloader-configuration)
   (feature-file-systems
    #:file-systems reform-file-systems)
   (feature-kernel
    #:kernel linux-libre-arm64-mnt-reform
    #:firmware (list (@ (nongnu packages linux) linux-firmware))
    #:base-initrd-modules %reform-initrd-modules)
   (feature-custom-services
    #:system-services reform-custom-services)))

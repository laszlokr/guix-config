(define-module (configs hosts reform)
  #:use-module (gnu bootloader)
  #:use-module (gnu bootloader extlinux)
  #:use-module (gnu packages linux)
  #:use-module (gnu services)
  #:use-module (gnu services ssh)
  #:use-module (gnu system)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system shadow)
  #:use-module (srfi srfi-1)
  #:use-module (rde features)
  #:use-module (rde features base)
  #:use-module (rde features system)
  #:use-module (rde system services accounts))

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
  ;; %base-initrd-modules must NOT be used here.  It expands to
  ;; (default-initrd-modules) evaluated against (%current-system) -- and
  ;; rde's feature-kernel takes it as a keyword default, so building this
  ;; host from x86_64 produces a list describing an x86 desktop.  The
  ;; initrd build then dies on the first name this kernel does not ship:
  ;;
  ;;   gnu/build/linux-modules.scm:278:5: kernel module not found "uas"
  ;;
  ;; It is not only the obviously-x86 entries.  Of the 24 modules in the
  ;; base list, exactly seven exist in linux-libre-arm64-mnt-reform's
  ;; module tree: nvme, dm-crypt, virtio_pci, virtio_balloon, virtio_blk,
  ;; virtio_net and virtio_mmio.  The rest are either built into this
  ;; kernel (usbhid, mmc_block, xts, nls_iso8859-1 ...) or absent
  ;; (ahci, uas, isci, pata_*).  Built-in is fine -- it just means they
  ;; must not be named as initrd modules.
  ;;
  ;; ext4 is built in too, so the root file system needs nothing here;
  ;; base-initrd derives file-system modules from the file-systems field
  ;; anyway.  What the initrd genuinely needs is the block controller.
  ;;
  ;; Re-derive after a kernel bump:
  ;;   find $(guix build -e '(@ (gnu packages linux) \
  ;;     linux-libre-arm64-mnt-reform)')/lib/modules -name '<module>.ko*'
  '("nvme"                              ;root device lives on the NVMe
    "dm-crypt"))                        ;leaves room for a LUKS root later


;;; Kernel command line
;;
;; Taken from what MNT's own U-Boot passes on this machine -- read out of
;; the bootloader's compiled-in environment on the SD card:
;;
;;   bootargs=ro no_console_suspend console=ttyAML0,115200 pci=pcie_bus_perf \
;;            libata.force=noncq nvme_core.default_ps_max_latency_us=0 console=tty1
;;
;; Guix supplies its own --root=/--system= arguments, and `ro' is the
;; initrd's business, so only the hardware-relevant ones are carried over.
;; libata.force=noncq is dropped too: there is no SATA on this machine.

(define %reform-kernel-arguments
  (list
   ;; The A311D's serial console, same port U-Boot uses (S2, 115200); tty1
   ;; keeps output on the internal panel as well.
   "console=ttyAML0,115200"
   "console=tty1"
   ;; Without this the NVMe drops off the bus when it enters a deep APST
   ;; power state -- MNT ship it by default on this platform.
   "nvme_core.default_ps_max_latency_us=0"
   "pci=pcie_bus_perf"
   ;; Keep console output alive across suspend, for debugging early boot.
   "no_console_suspend"))


;;; Host-specific services

(define reform-custom-services
  (list
   (service openssh-service-type
            (openssh-configuration
             (password-authentication? #f)
             (permit-root-login 'prohibit-password)))))


;;; Architecture fixup applied after the features are folded
;;
;; This host does not run VMs -- 4 GB of RAM -- so configs.scm drops the
;; shared feature set's `qemu' feature.  That also sidesteps a hard
;; aarch64 blocker, worth recording since it is invisible until you build:
;;
;;   feature-qemu instantiates libvirt-service-type, whose `firmwares'
;;   field defaults to (list ovmf-x86-64).  ovmf-x86-64 does not build on
;;   aarch64 -- EDK2 compiles its X64 modules with the native aarch64 gcc,
;;   which rejects the x86 flags it passes ("gcc: error: unrecognized
;;   command-line option '-m64'", likewise -mno-red-zone, -mno-mmx,
;;   -maccumulate-outgoing-args) -- and no substitute server carries an
;;   aarch64 build of it.  Nor can the field simply be pointed at
;;   ovmf-aarch64: libvirt builds /etc/qemu/firmware by union-ing
;;   <pkg>/share/qemu/firmware, and ovmf-x86-64 is the only package in guix
;;   that installs that directory, so the union's opendir fails.  Anyone
;;   reviving virtualization here would have to set `firmwares' to '().
;;
;; Dropping the feature leaves the "libvirt" group undeclared -- it was
;; libvirt-service-type that declared it -- while feature-user-info in the
;; shared user config still lists it among laszlokr's supplementary groups.
;; `guix system' rejects that outright: "supplementary group 'libvirt' of
;; user 'laszlokr' is undeclared".
;;
;; Rather than fork feature-user-info for this one host (it also carries the
;; name, email and password hash), filter the group out of the account after
;; the features are folded.  rde attaches the user through
;; rde-account-service-type rather than the operating-system `users' field,
;; so the account is reached with modify-services.

(define %reform-absent-groups
  ;; Supplementary groups the shared user config asks for that no service on
  ;; this host declares.
  '("libvirt"))

(define (drop-absent-groups account)
  (user-account
   (inherit account)
   (supplementary-groups
    (remove (lambda (group) (member group %reform-absent-groups))
            (user-account-supplementary-groups account)))))

(define-public (reform-operating-system config)
  "Return the <operating-system> for CONFIG, an <rde-config>, with the
architecture fixups this host needs."
  (let ((os (rde-config-operating-system config)))
    (operating-system
     (inherit os)
     (services
      (modify-services (operating-system-user-services os)
        (rde-account-service-type account => (drop-absent-groups account)))))))


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
    #:base-initrd-modules %reform-initrd-modules
    #:kernel-arguments %reform-kernel-arguments)
   (feature-custom-services
    #:system-services reform-custom-services)))

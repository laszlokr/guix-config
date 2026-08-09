(define-module (configs hosts reform)
  #:use-module (gnu bootloader)
  #:use-module (gnu bootloader extlinux)
  #:use-module (gnu home)
  #:use-module (gnu home services)
  #:use-module (gnu packages)
  #:use-module (gnu packages glib)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (gnu packages linux)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services ssh)
  #:use-module (gnu system)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system mapped-devices)
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
   ;; IMPORTANT: /boot must live on the root file system -- not on a
   ;; separate partition, and not on an encrypted one.  extlinux.conf
   ;; references the kernel and initrd by absolute /gnu/store/... path,
   ;; and U-Boot resolves those paths on the partition it loaded
   ;; extlinux.conf from.  A separate /boot would send it looking for
   ;; /gnu/store on a partition that does not have it; an encrypted root
   ;; would put the store somewhere U-Boot cannot read at all.
   ;;
   ;; This machine's U-Boot can reach the NVMe -- its compiled-in
   ;; environment has the full nvme command set, bootcmd_nvme0 and PCIe
   ;; enumeration:
   ;;
   ;;   boot_targets=romusb mmc0 mmc1 mmc2 usb0 nvme0 pxe dhcp
   ;;   U-Boot 2024.04-dirty (Oct 11 2024) bpi-cm4-mnt-reform2
   ;;
   ;; but note nvme0 is tried *after* the mmc targets, so the SD card wins
   ;; until boot_targets is reordered and saved from the U-Boot prompt.
   (targets (list "/boot"))
   ;; Emits "FDTDIR <kernel>/lib/dtbs" so U-Boot picks the device tree
   ;; named by its own $fdtfile -- meson-g12b-bananapi-cm4-mnt-reform2.dtb
   ;; on this module.  (#t is the default; stated explicitly because it is
   ;; load-bearing on this machine.)
   (device-tree-support? #t)
   (timeout 3)))


;;; Storage layout
;;
;;   nvme0n1p1  ext4                        /        (unencrypted)
;;   nvme0n1p2  LUKS2 -> LVM "reformdata" ┬ /home
;;                                        └ swap
;;
;; The root partition is deliberately NOT encrypted, and that is forced by
;; the bootloader, not by preference.  U-Boot cannot decrypt LUKS, and
;; extlinux.conf names the kernel and initrd by absolute /gnu/store/...
;; path which U-Boot resolves on the partition it read the config from.
;; So the kernel, the initrd and the store must all sit on one partition
;; U-Boot can read.  Encrypt the store and `guix system reconfigure' stops
;; being self-contained: every generation would need its kernel copied out
;; to a readable partition by hand, and rollback would stop being a
;; boot-menu choice.
;;
;; What that leaves readable to someone holding the disk: the package
;; list, /etc, and the system logs.  What stays encrypted: /home -- the
;; documents, keys and mail -- and swap, so memory contents do not leak to
;; the platter.  A single LUKS container holds both, so it is one
;; passphrase at boot.
;;
;; The UUIDs below are the real ones from the installed disk.  If the
;; drive is ever reformatted, re-read them with:
;;
;;     sudo blkid /dev/nvme0n1p1        # root, the "ext4" UUID
;;     sudo blkid /dev/nvme0n1p2        # the LUKS *container* UUID
;;
;; and note the second is the crypto_LUKS partition itself, not the ext4
;; inside it.  `guix system init' run as root calls
;; check-file-system-availability, so a stale UUID fails loudly at install
;; time rather than at boot.
;;
;; The root file system must be made with U-Boot-compatible feature flags
;; (-O ^metadata_csum_seed,^orphan_file); see doc/reform-install.md.

(define %reform-root-uuid
  ;; /dev/nvme0n1p1, ext4, label "guix-root"
  (uuid "5949e666-5bb5-439c-ada1-6bdaba9928bb"))

(define %reform-luks-uuid
  ;; /dev/nvme0n1p2, the crypto_LUKS *container* -- not the ext4 inside it
  (uuid "17ea655c-8cfe-4c2f-af28-cc87af93f805"))

(define reform-mapped-devices
  ;; Neither of these is needed-for-boot: root is plain ext4, so the initrd
  ;; never touches them.  They are opened later in the boot sequence, which
  ;; also means a mistyped passphrase costs you /home and swap, not the
  ;; system -- you still get a shell.
  (list
   (mapped-device
    (source %reform-luks-uuid)
    (target "reformdata-crypt")
    (type luks-device-mapping))
   (mapped-device
    (source "reformdata")
    (targets (list "reformdata-home" "reformdata-swap"))
    (type lvm-device-mapping))))

(define reform-file-systems
  (list
   (file-system
    (mount-point "/")
    (device %reform-root-uuid)
    (type "ext4"))
   (file-system
    (mount-point "/home")
    (device "/dev/mapper/reformdata-home")
    (type "ext4")
    (dependencies reform-mapped-devices))))

(define reform-swap-devices
  (list
   (swap-space
    (target "/dev/mapper/reformdata-swap")
    (dependencies reform-mapped-devices))))


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
;; Banana Pi CM4's Wi-Fi/Bluetooth is a Realtek RTL8822CS SDIO combo chip
;; (driver rtw88/rtw8822cs) that needs rtw88/rtw8822c_fw.bin.  The kernel
;; itself is the libre one; only the firmware is nonfree.

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
   ;; The A311D's serial console, same port U-Boot uses (S2, 115200).
   "console=ttyAML0,115200"
   ;; Without this the NVMe drops off the bus when it enters a deep APST
   ;; power state -- MNT ship it by default on this platform.
   "nvme_core.default_ps_max_latency_us=0"
   "pci=pcie_bus_perf"
   ;; Keep console output alive across suspend, for debugging early boot.
   "no_console_suspend"
   ;; MUST be the LAST console= argument (see flash-kernel's own
   ;; /usr/share/flash-kernel/ubootenv.d/00reform2_ubootenv on this
   ;; machine): the kernel treats the last-registered console as primary,
   ;; and that is where interactive prompts -- specifically the /home LUKS
   ;; passphrase prompt at boot -- get shown.  Putting it anywhere earlier
   ;; risks that prompt landing on the serial line instead of the internal
   ;; panel, which is unusable without a UART cable connected.
   "console=tty1"))


;;; Host-specific services

(define reform-custom-services
  (list
   (service openssh-service-type
            (openssh-configuration
             (password-authentication? #f)
             (permit-root-login 'prohibit-password)))
   ;; rde's greetd sway session wraps the compositor in `dbus-run-session'
   ;; (see (rde system services greetd) greetd-login-session-with-dbus):
   ;;
   ;;   execl <dbus>/bin/dbus-run-session <dbus>/bin/dbus-run-session -- sway
   ;;
   ;; `dbus-run-session' itself is found fine, by absolute store path.  But
   ;; internally it spawns the *session* bus by searching plain $PATH for
   ;; "dbus-daemon" -- it is never given an absolute path, and nothing put
   ;; dbus on $PATH system-wide.  The *system* bus works regardless (the
   ;; dbus-system shepherd service references the package directly, no
   ;; $PATH needed), which is why NetworkManager/PolicyKit are fine while
   ;; every graphical login fails immediately with:
   ;;
   ;;   dbus-run-session: failed to execute message bus daemon
   ;;   'dbus-daemon': No such file or directory
   ;;
   ;; Adding dbus to the system profile puts its bin/ on the default
   ;; PATH, which is all dbus-run-session needs to find it.
   (simple-service 'reform-dbus-on-path
                   profile-service-type
                   (list dbus))
   ;; The RTL8822CS's rtw88 firmware has a known low-power-state bug on
   ;; this exact module -- see MNT's own forum thread "A311D wifi issues,
   ;; 'firmware failed to leave lps state', disconnects"
   ;; (community.mnt.re/t/2112) -- that drops the connection every
   ;; 60s-15min under NetworkManager's default Wi-Fi power-saving.  This is
   ;; very likely most of what makes "stock Reform wifi" look weak, as
   ;; opposed to the antenna itself.  wifi.powersave = 2 disables power
   ;; saving outright (NM's enum: 0 default, 1 ignore, 2 disable, 3 enable).
   (simple-service 'reform-wifi-disable-powersave
                   etc-service-type
                   (list (list "NetworkManager/conf.d/wifi-powersave-off.conf"
                               (plain-file
                                "wifi-powersave-off.conf"
                                "[connection]\nwifi.powersave = 2\n"))))))


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


;;; Home-side architecture fixup
;;
;; users/laszlokr.scm is shared with box and lists these packages among the
;; home-profile-extra-packages -- fine on x86_64, but none of them have an
;; aarch64 substitute on bordeaux (measured 0.0% for each), and all three
;; are full from-source compiles of large C/C++ codebases (openscad pulls
;; in CGAL; firefox is nongnu's gnu-build-system source build, not a binary
;; repackage; libreoffice is glib-or-gtk-build-system and one of the
;; largest builds in Guix).  Each is a many-hour build on a 4 GB A311D and
;; a strong OOM-kill candidate (openscad/CGAL confirmed OOM-killed on
;; cc1plus after ~29 minutes).  Filtered out for this host only; box keeps
;; them unchanged.  librewolf remains as this host's browser.  Re-check
;; with:
;;
;;   guix weather --system=aarch64-linux openscad firefox libreoffice

(define %reform-absent-profile-packages
  ;; Matched by package name, not by identity: the package objects here
  ;; come from the (rde …) closure, not from this module.
  '("openscad" "firefox" "libreoffice"))

;; home-profile-service-type is only ever *instantiated* as an essential
;; service (seeded from home-environment-packages); the package list our
;; own users/laszlokr.scm contributes -- and every other one contributed
;; by an rde feature -- is a separate, anonymously-typed service that just
;; *extends* it.  There is no bound service-type to hand `modify-services'
;; for any single one of those, so filter generically: walk every user
;; service, and for any whose type extends home-profile-service-type,
;; drop the absent packages from its value.  Entries may be a bare
;; <package> or a (package output) pair (see the "packages" field comment
;; in gnu/home.scm), hence the two-armed name lookup.
(define (package-entry-name entry)
  (package-name (if (pair? entry) (car entry) entry)))

(define (extends-home-profile? svc)
  (any (lambda (ext) (eq? (service-extension-target ext) home-profile-service-type))
       (service-type-extensions (service-kind svc))))

(define (drop-absent-profile-packages svc)
  (if (and (extends-home-profile? svc) (list? (service-value svc)))
      (service (service-kind svc)
               (remove (lambda (entry)
                         (member (package-entry-name entry)
                                 %reform-absent-profile-packages))
                       (service-value svc)))
      svc))

;; libreoffice is dropped above (no aarch64 substrate, OOM-kill risk), but
;; this host still needs something for word documents and spreadsheets.
;; AbiWord + Gnumeric cover that and are both fully substitutable on
;; aarch64 (measured: 100% on bordeaux), so no local build at all.  Re-check
;; with:
;;
;;   guix weather --system=aarch64-linux abiword gnumeric
(define reform-extra-profile-service
  (simple-service 'reform-office-suite
                  home-profile-service-type
                  (map specification->package '("abiword" "gnumeric"))))

(define-public (reform-home-environment config)
  "Return the <home-environment> for CONFIG, an <rde-config>, with the
architecture fixups this host needs."
  (let ((he (rde-config-home-environment config)))
    (home-environment
     (inherit he)
     (services
      (cons reform-extra-profile-service
            (map drop-absent-profile-packages
                 (home-environment-user-services he)))))))


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
    #:file-systems reform-file-systems
    #:mapped-devices reform-mapped-devices
    #:swap-devices reform-swap-devices)
   (feature-kernel
    #:kernel linux-libre-arm64-mnt-reform
    #:firmware (list (@ (nongnu packages linux) linux-firmware))
    #:base-initrd-modules %reform-initrd-modules
    #:kernel-arguments %reform-kernel-arguments)
   (feature-custom-services
    #:system-services reform-custom-services)))

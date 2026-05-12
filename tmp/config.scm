(use-modules (gnu))
(use-modules (gnu system))
(use-modules (gnu services))
(use-modules (gnu services base))
(use-modules (gnu services ssh))
(use-modules (gnu services networking))
(use-modules (gnu services sound))
(use-modules (gnu packages linux))
(use-modules (gnu packages))
(use-modules (nongnu packages linux))
(use-modules (mnt-reform a311d))

(operating-system
  (host-name "reform")
  (timezone "Europe/Zurich")
  (locale "en_US.utf8")

  (bootloader (bootloader-configuration
                (bootloader u-boot-a311d-bootloader)
                (targets '("/dev/nvme0n1"))))

  (kernel linux-mnt-reform-a311d-6.6)
  (kernel-arguments '("nvme_core.default_ps_max_latency_us=0"
                      "libata.force=noncq"
                      "pci=pcie_bus_perf"))

  (file-systems (cons*
    (file-system
      (mount-point "/boot")
      (device (file-system-label "BOOT"))
      (type "ext4"))
    (file-system
      (mount-point "/")
      (device (file-system-label "ROOT"))
      (type "ext4"))
    %base-file-systems))

  (users (cons (user-account
                 (name "laszlokr")
                 (comment "Laszlo Krajnikovszkij")
                 (group "users")
                 (supplementary-groups '("wheel" "netdev" "audio" "video" "input")))
               %base-user-accounts))

  (services
   (cons*
    (service openssh-service-type
             (openssh-configuration
              (permit-root-login #t)
              (password-authentication? #f)))

    (service dhcp-client-service-type)

    (service alsa-service-type)

    %base-services))

  (packages
   (append
    (list vim htop parted cryptsetup openssh ntp wget pciutils usbutils linux-firmware)
    %base-packages))

  (environment-variables
   '(("EDITOR" . "vim")
     ("LC_ALL" . "en_US.utf8")
     ("LANG" . "en_US.utf8")))

  (sudoers-file
   (plain-file "sudoers"
               "root ALL=(ALL) ALL\n%wheel ALL=(ALL) NOPASSWD: ALL\n"))

  (keyboard-layout
   (keyboard-layout "us" "altgr-intl"))
)

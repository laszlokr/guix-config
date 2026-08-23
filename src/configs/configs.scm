(define-module (configs configs)
  #:use-module (rde features)
  #:use-module (gnu home)
  #:use-module (gnu home services)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (rde home services emacs)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (ice-9 match)
  #:use-module (configs hosts box)
  ;; #:use-module (configs hosts mintsystem)  ;; uncomment after filling in UUIDs
  #:use-module (configs hosts reform)
  ;; #:use-module (configs hosts pi4)  ;; uncomment once the base bring-up
  ;; milestone in hosts/pi4.scm's own header comment is actually done --
  ;; this file is scaffolding, not build-ready.  See that file for why.
  #:use-module (configs users laszlokr))

;;; configs

;; emacs-feature-loader fails to build with autoloads? #t: the generated
;; autoloads file gets a top-level (feature-loader) call, and the
;; emacs-build-system's validate-compiled-autoloads phase loads that file in
;; headless batch Emacs, where the call pulls in rde runtime libraries
;; (rde-fonts -> fontaine -> modus-themes) that need a display.  There is no
;; public substitute server for rde packages, so it must build from source.
;;
;; With autoloads? #f the bare call is not emitted at all (see
;; home-emacs-feature-loader-packages in (rde home services emacs)), so the
;; package builds.
;;
;; autoloads? #f alone leaves Emacs unconfigured, because then nothing loads
;; the feature-loader at all.  add-to-init-el? #t puts a plain
;; (require 'feature-loader) in init.el instead, so features still load
;; eagerly at startup -- just through a normal require in a real Emacs
;; session rather than an autoload cookie evaluated by headless batch Emacs
;; during validate-compiled-autoloads.
;;
;; That alone still isn't enough: restoring real activation surfaces a
;; SEPARATE bug in rde's generated code, where rde-fonts' after-init-hook
;; entry can fire before rde-modus-themes' has loaded modus-themes.el,
;; crashing on a void modus-themes-get-current-theme.  See the
;; with-demoted-errors block in users/laszlokr.scm's init-el for the fix.
(define (fix-feature-loader he)
  (home-environment
   (inherit he)
   (services
    (modify-services (home-environment-user-services he)
      (home-emacs-feature-loader-service-type
       config => (home-emacs-feature-loader-configuration
                  (inherit config)
                  (autoloads? #f)
                  (add-to-init-el? #t)))))))

;; feature-podman hardcodes the btrfs storage driver:
;;
;;     ("containers/storage.conf"
;;      ,(plain-file "storage.conf" "[storage]\ndriver = \"btrfs\""))
;;
;; with no keyword argument to change it. box and reform are both on ext4, so
;; podman fails outright:
;;
;;     Error: configure storage: ".../storage/btrfs" is not on a btrfs
;;     filesystem: prerequisites for driver not satisfied
;;
;; Adding a second service declaring the same file is a duplicate-entry
;; collision, not an override. Instead, replace the existing entry in place.
;;
;; Matched by path rather than by service type: modify-services on
;; home-xdg-configuration-files-service-type fails with
;;
;;     error: modify-services: service 'home-xdg-configuration' not found
;;
;; because that type has no direct instance in the service list here. Walking
;; the services and rewriting any entry whose path ends in
;; containers/storage.conf works whichever service ultimately carries it, and
;; is a no-op if the entry is absent.
(define (fix-podman-storage-driver he)
  (define overlay-storage-conf
    (plain-file "storage.conf" "[storage]\ndriver = \"overlay\"\n"))

  (define (replace-entry entry)
    (if (and (pair? entry)
             (string? (car entry))
             (string-suffix? "containers/storage.conf" (car entry)))
        (list (car entry) overlay-storage-conf)
        entry))

  (define (replace-in-service s)
    (let ((value (service-value s)))
      (if (list? value)
          (service (service-kind s) (map replace-entry value))
          s)))

  (home-environment
   (inherit he)
   (services (map replace-in-service (home-environment-user-services he)))))

;; box — Minisforum HX90 mini PC, runs full Guix system
(define-public box-config
  (rde-config
   (features
    (append
     %box-features
     %laszlokr-features))))

(define-public box-os
  (rde-config-operating-system box-config))

(define-public box-he
  (fix-podman-storage-driver
   (fix-feature-loader
    (rde-config-home-environment box-config))))

;; reform — MNT Reform with a Banana Pi CM4 module (A311D, aarch64),
;; full Guix system on NVMe.  Same feature set as the other hosts; only the
;; hardware bits differ.
;;
;; Three features from the shared set are dropped for this host:
;;
;;   kernel — pins the x86 nonguix kernel, and rde raises on duplicate
;;     feature values, so %reform-features supplies the MNT Reform arm64
;;     kernel instead.
;;
;;   qemu — no VMs on this machine; 4 GB of RAM.  Dropping it also avoids
;;     ovmf-x86-64, which cannot be built for aarch64 at all; see the
;;     comment in hosts/reform.scm.
;;
;;   ungoogled-chromium — has *no* aarch64 substitute on bordeaux (measured:
;;     0.0% available, versus 100% for librewolf and icecat), so `guix home
;;     reconfigure' silently drops into compiling Chromium from source.  On a
;;     4 GB A311D that is a many-hour build that will most likely be OOM-killed
;;     before it finishes.  librewolf stays and remains fully substitutable,
;;     so this host still has a browser.  Re-check with:
;;
;;       guix weather --system=aarch64-linux ungoogled-chromium
;;
;;   guile — feature-guile puts guile-ares-rs in the home profile, and on
;;     aarch64 that collides irreconcilably with shepherd:
;;
;;       profile contains conflicting entries for guile-fibers
;;         guile-fibers@1.4.3 ... propagated from guile-ares-rs
;;         guile-fibers@1.1.1 ... propagated from shepherd@1.0.9
;;
;;     This is architecture-specific by design.  guix's shepherd package
;;     does, in gnu/packages/admin.scm:
;;
;;       (replace "guile-fibers"
;;         ;; Work around <https://codeberg.org/guile/fibers/issues/89>.
;;         ;; This affects any system without a functional real-time clock
;;         ;; (RTC), but in practice these are typically single-board
;;         ;; computers.
;;         (if (or (target-arm?) (target-riscv64?))
;;             guile-fibers-1.1
;;             guile-fibers))
;;
;;     so on ARM shepherd is deliberately held at fibers 1.1 while
;;     guile-ares-rs tracks the latest.  Nothing to fix locally -- the two
;;     cannot share a profile here.  box is unaffected, which is exactly why
;;     the same home config builds there and not on the Reform.
;;
;;     Cost: emacs-arei / the Guile nREPL workflow.  Guile itself is
;;     unaffected; it stays available system-wide.
(define %reform-dropped-features '(kernel qemu ungoogled-chromium guile))

(define %laszlokr-features/reform
  (remove (lambda (f) (memq (feature-name f) %reform-dropped-features))
          %laszlokr-features))

(define-public reform-config
  (rde-config
   (features
    (append
     %reform-features
     %laszlokr-features/reform))))

;; Not rde-config-operating-system directly: this host needs one
;; architecture fixup applied after the features are folded.  See
;; hosts/reform.scm.
(define-public reform-os
  (reform-operating-system reform-config))

;; Not rde-config-home-environment directly: same reasoning as reform-os,
;; see hosts/reform.scm. fix-podman-storage-driver applies here too --
;; reform's root and home are both ext4, same as box, same btrfs-hardcoded
;; podman failure otherwise.
(define-public reform-he
  (fix-podman-storage-driver
   (fix-feature-loader
    (reform-home-environment reform-config))))

;; mintsystem — HP laptop, home environment only
;; (commented out until mintsystem.scm has real UUIDs)
;; (define-public mintsystem-config
;;   (rde-config
;;    (features
;;     (append
;;      %mintsystem-features
;;      %laszlokr-features))))
;;
;; (define-public mintsystem-he
;;   (rde-config-home-environment mintsystem-config))

;; pi4 — Raspberry Pi 4, home mesh gateway + .lan DNS + substitute cache.
;; No home-config generation (system only, headless, no desktop features
;; apply at all here) -- same reasoning box-he/reform-he don't apply to
;; this host.  Commented out along with the #:use-module above until the
;; base bring-up milestone in hosts/pi4.scm is done; that file is
;; scaffolding, not build-ready.
;; (define-public pi4-config
;;   (rde-config
;;    (features %pi4-features)))
;;
;; (define-public pi4-os
;;   (rde-config-operating-system pi4-config))


(define (dispatcher)
  (let ((rde-target (getenv "RDE_TARGET")))
    (match rde-target
      ("box-home" box-he)
      ("box-system" box-os)
      ("reform-home" reform-he)
      ("reform-system" reform-os)
      ;; ("mintsystem-home" mintsystem-he)
      ;; ("pi4-system" pi4-os)
      (_ box-he))))

(dispatcher)

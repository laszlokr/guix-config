(define-module (configs configs)
  #:use-module (rde features)
  #:use-module (gnu home)
  #:use-module (gnu services)
  #:use-module (rde home services emacs)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:use-module (configs hosts box)
  ;; #:use-module (configs hosts mintsystem)  ;; uncomment after filling in UUIDs
  ;; reform needs lykso's checkout on the load path for (mnt-reform a311d);
  ;; uncomment together with reform-os below and build via `make reform/system/build`,
  ;; which passes the required -L.  Leaving it imported unconditionally would
  ;; break box builds, which have no such module.
  ;; #:use-module (configs hosts reform)
  #:use-module (configs users laszlokr))


;;; configs

;; box — Minisforum HX90 mini PC, runs full Guix system
(define-public box-config
  (rde-config
   (features
    (append
     %box-features
     %laszlokr-features))))

(define-public box-os
  (rde-config-operating-system box-config))

;; emacs-feature-loader fails to build with autoloads? #t: the generated
;; autoloads file gets a top-level (feature-loader) call, and the
;; emacs-build-system's validate-compiled-autoloads phase loads that file in
;; headless batch Emacs, where the call pulls in rde runtime libraries
;; (rde-fonts -> fontaine -> modus-themes) that need a display.  There is no
;; public substitute server for rde packages, so it must build from source.
;;
;; With autoloads? #f the bare call is not emitted at all (see
;; home-emacs-feature-loader-packages in (rde home services emacs)), so the
;; package builds.  Trade-off: features are loaded lazily on `require' rather
;; than eagerly at Emacs startup; run M-x feature-loader to force-load.
(define (disable-feature-loader-autoloads he)
  (home-environment
   (inherit he)
   (services
    (modify-services (home-environment-user-services he)
      (home-emacs-feature-loader-service-type
       config => (home-emacs-feature-loader-configuration
                  (inherit config)
                  (autoloads? #f)))))))

(define-public box-he
  (disable-feature-loader-autoloads
   (rde-config-home-environment box-config)))

;; reform — MNT Reform (full-size) with Banana Pi CM4 / A311D, aarch64
;; (commented out until reform.scm has real NVMe UUIDs and lykso's checkout
;; is available; see src/configs/hosts/reform.scm)
;; (define-public reform-config
;;   (rde-config
;;    (features
;;     (append
;;      %reform-features
;;      %laszlokr-features))))
;;
;; (define-public reform-os
;;   (rde-config-operating-system reform-config))

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


(define (dispatcher)
  (let ((rde-target (getenv "RDE_TARGET")))
    (match rde-target
      ("box-home" box-he)
      ("box-system" box-os)
      ;; ("reform-system" reform-os)
      ;; ("mintsystem-home" mintsystem-he)
      (_ box-he))))

(dispatcher)

(define-module (configs configs)
  #:use-module (configs patches)
  #:use-module (rde features)
  #:use-module (gnu services)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:use-module (configs hosts box)
  ;; #:use-module (configs hosts mintsystem)  ;; uncomment after filling in UUIDs
  #:use-module (configs hosts reform)
  #:use-module (configs users laszlokr))

(apply-patches!)

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

(define-public box-he
  (rde-config-home-environment box-config))

;; reform — MNT Reform with a Banana Pi CM4 module (A311D, aarch64),
;; full Guix system on NVMe.  Same feature set as the other hosts; only the
;; hardware bits differ.
;;
;; %laszlokr-features pins the x86 nonguix kernel, and rde raises on
;; duplicate feature values, so the shared 'kernel feature is dropped here
;; and %reform-features supplies the MNT Reform arm64 kernel instead.
(define %laszlokr-features/no-kernel
  (remove (lambda (f) (eq? (feature-name f) 'kernel)) %laszlokr-features))

(define-public reform-config
  (rde-config
   (features
    (append
     %reform-features
     %laszlokr-features/no-kernel))))

(define-public reform-os
  (rde-config-operating-system reform-config))

(define-public reform-he
  (rde-config-home-environment reform-config))

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
      ("reform-home" reform-he)
      ("reform-system" reform-os)
      ;; ("mintsystem-home" mintsystem-he)
      (_ box-he))))

(dispatcher)

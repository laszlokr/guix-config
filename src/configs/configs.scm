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
;; Two features from the shared set are dropped for this host:
;;
;;   kernel — pins the x86 nonguix kernel, and rde raises on duplicate
;;     feature values, so %reform-features supplies the MNT Reform arm64
;;     kernel instead.
;;
;;   qemu — no VMs on this machine; 4 GB of RAM.  Dropping it also avoids
;;     ovmf-x86-64, which cannot be built for aarch64 at all; see the
;;     comment in hosts/reform.scm.
(define %reform-dropped-features '(kernel qemu))

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

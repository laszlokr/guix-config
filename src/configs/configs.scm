(define-module (configs configs)
  #:use-module (rde features)
  #:use-module (gnu services)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:use-module (configs hosts box)
  ;; #:use-module (configs hosts mintsystem)
  #:use-module (configs users laszlokr))

(define* (use-nested-configuration-modules
          #:key
          (users-subdirectory "/users")
          (hosts-subdirectory "/hosts"))
  (use-modules (guix discovery)
               (guix modules))

  (define current-module-file
    (search-path %load-path
                 (module-name->file-name (module-name (current-module)))))

  (define current-module-directory
    (dirname (and=> current-module-file canonicalize-path)))

  (define src-directory
    (dirname current-module-directory))

  (define current-module-subdirectory
    (string-drop current-module-directory (1+ (string-length src-directory))))

  (define users-modules
    (scheme-modules
     src-directory
     (string-append current-module-subdirectory users-subdirectory)))

  (define hosts-modules
    (scheme-modules
     src-directory
     (string-append current-module-subdirectory hosts-subdirectory)))

  (map (lambda (x) (module-use! (current-module) x)) hosts-modules)
  (map (lambda (x) (module-use! (current-module) x)) users-modules))

(use-nested-configuration-modules)


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

;; mintsystem — HP laptop, home environment only
(define-public mintsystem-config
  (rde-config
   (features
    (append
     %mintsystem-features
     %laszlokr-features))))

(define-public mintsystem-he
  (rde-config-home-environment mintsystem-config))


(define (dispatcher)
  (let ((rde-target (getenv "RDE_TARGET")))
    (match rde-target
      ("box-home" box-he)
      ("box-system" box-os)
      ("mintsystem-home" mintsystem-he)
      (_ box-he))))

(dispatcher)

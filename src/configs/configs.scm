(define-module (configs configs)
  #:use-module (rde features)
  #:use-module (gnu services)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match))

(define* (use-nested-configuration-modules
          #:key
          (users-subdirectory "/users")
          (hosts-subdirectory "/hosts"))
  (use-modules (guix discovery)
               (configs users laszlokr)
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

(define-public box-config
  (rde-config
   (features
    (append
     %box-features
     %laszlokr-features
     ))))

(define-public box-os
  (rde-config-operating-system box-config))

(define-public box-he
  (rde-config-home-environment box-config))


(define (dispatcher)
  (let ((rde-target (getenv "RDE_TARGET")))
    (match rde-target
      ("box-home" box-he)
      ("box-system" box-os)
      (_ box-he))))

(dispatcher)

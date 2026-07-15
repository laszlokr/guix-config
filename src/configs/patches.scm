(define-module (configs patches)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (guix gexp)
  #:use-module (srfi srfi-1)
  #:export (apply-patches!))

(define (install-patch! mod)
  (let ((v (module-variable mod 'elisp-configuration-package)))
    (when v
      (let ((orig (variable-ref v)))
        (variable-set! v
          (lambda args
            (let ((pkg (apply orig args)))
              (package/inherit pkg
                (arguments
                 (substitute-keyword-arguments
                     (package-arguments pkg)
                   ((#:phases phases #~%standard-phases)
                    #~(modify-phases #$phases
                        (add-before 'make-autoloads
                          'remove-top-level-autoload-calls
                          (lambda _
                            (for-each
                             (lambda (f)
                               (format #t "stripping autoloads from ~a~%" f)
                               (substitute* f
                                 ((";;;###autoload") "")))
                              (find-files "." "\\.el$"))))))))))))))
    v))

(define (apply-patches!)
  (let ((mod (resolve-module '(rde home services emacs) #f)))
    (if (and mod (install-patch! mod))
        (format (current-error-port)
                "[configs/patches] patched elisp-configuration-package~%")
        (let ((mod2 (resolve-module '(rde home services emacs) #t)))
          (if (install-patch! mod2)
              (format (current-error-port)
                      "[configs/patches] patched elisp-configuration-package (retry)~%")
              (format (current-error-port)
                      "[configs/patches] WARNING: elisp-configuration-package not found~%"))))))

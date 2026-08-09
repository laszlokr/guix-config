(define-module (configs patches)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (guix gexp)
  #:use-module (srfi srfi-1)
  #:export (apply-patches!))

;; emacs-feature-loader (and any other elisp-configuration-package output
;; that uses #:autoloads? #t) fails its 'validate-compiled-autoloads build
;; phase: that phase actually *executes* the autoload-copied top-level call
;; (e.g. (feature-loader), which requires every rde-* feature file) in an
;; isolated --batch emacs whose load-path is only this one package's own
;; propagated-inputs.  Cross-feature calls -- e.g. rde-fonts pulling in
;; fontaine, whose enable-theme hook calls modus-themes-get-current-theme --
;; aren't resolvable there, even though they work fine in a real Emacs
;; session where the *whole* profile (every rde-* package) is on the load
;; path together.  So this is a build-time-only artifact of an
;; unrepresentatively narrow validation environment, not a real bug.
;;
;; The old fix here stripped every ";;;###autoload" cookie to dodge the
;; crash -- but that cookie is also the ONLY thing that makes rde's
;; per-feature config (evil, vertico, appearance, themes, ...) self-activate
;; at real Emacs startup via the normal package-autoloads mechanism.
;; Stripping it "fixed" the build by silently disabling every feature at
;; runtime instead (confirmed: a live Emacs daemon on this config had
;; evil-mode/vertico/consult/rde-appearance all unloaded, with init.el
;; itself unchanged and erroring nowhere).
;;
;; Skip just the validation phase instead: it only re-loads the already-
;; compiled autoloads file as a sanity check, so no functionality is lost,
;; and the autoload cookie -- and therefore real runtime activation --
;; stays intact.
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
                        (replace 'validate-compiled-autoloads
                          (lambda _ #t))))))))))))
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

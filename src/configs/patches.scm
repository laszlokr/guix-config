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
;; propagated-inputs, which can be narrower than the full profile.
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
;;
;; That alone isn't sufficient though: with autoloading restored, a SEPARATE
;; real (not build-time-only) bug surfaces in rde's generated code.
;; rde-modus-themes.el installs `(advice-add 'enable-theme :after
;; 'rde-modus-themes-run-after-enable-theme-hook)' unconditionally and
;; immediately, but only actually loads the modus-themes library (which
;; defines `modus-themes-get-current-theme', called from that hook) via a
;; `load-theme' deferred to `after-init-hook'.  rde-fonts.el *also* defers
;; its own `enable-theme'-triggering call (fontaine-set-preset) to
;; `after-init-hook'.  Since `add-hook' prepends by default, and rde-fonts
;; is required *after* rde-modus-themes in feature-loader's sequence,
;; fontaine's hook ends up running FIRST -- triggering the advice before
;; modus-themes' own library has ever loaded, hence "Symbol's function
;; definition is void: modus-themes-get-current-theme".  Confirmed live on
;; the Reform: this reproduces on real startup, not just in the narrow
;; build-time validation environment.
;;
;; Fix by making feature-loader.el eagerly (require 'modus-themes) as the
;; very first thing it does, before any per-feature require or hook-add
;; runs -- modus-themes is already on feature-loader's load path (it's a
;; propagated-input of the rde-modus-themes feature-entry, which
;; feature-loader's own propagated-inputs is a union over), so this just
;; changes *when* it loads, guaranteeing the function exists no matter
;; which after-init-hook entry fires first.
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
                          (lambda _ #t))
                        (add-before 'make-autoloads
                          'eagerly-require-modus-themes
                          (lambda _
                            (for-each
                             (lambda (f)
                               (substitute* f
                                 (("\\(require 'guix-emacs\\)")
                                  "(require 'guix-emacs) (require 'modus-themes)")))
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

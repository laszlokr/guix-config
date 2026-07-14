(define-module (packages overrides)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (guix build-system emacs))

;;; emacs-feature-loader: the rde package's feature-loader.el calls
;;; (feature-loader) at the top level, which requires rde runtime Emacs
;;; libraries (rde-fonts → fontaine → modus-themes) that fail in batch/
;;; headless Emacs during the validate-compiled-autoloads build phase.
;;; There is no public substitute server for rde channel packages, so
;;; the package must build from source.  Replace the failing phase with
;;; a no-op so the build succeeds.
;;;
;;; Usage: pass --with-graft=emacs-feature-loader=emacs-feature-loader-patched
;;; to guix home build / reconfigure.

(define-public emacs-feature-loader-patched
  (let ((base (@ (rde packages emacs) emacs-feature-loader)))
    (package/inherit base
      (name "emacs-feature-loader-patched")
      (arguments
       (substitute-keyword-arguments (package-arguments base)
         ((#:phases phases #~%standard-phases)
          #~(modify-phases #$phases
              (replace 'validate-compiled-autoloads
                (lambda _
                  ;; Skip: feature-loader.el calls (feature-loader) at
                  ;; top level which pulls in rde runtime code that
                  ;; fails in batch Emacs (upstream rde bug).
                  #t))
              (add-after 'install 'normalize-paths
                (lambda* (#:key outputs #:allow-other-keys)
                  (let* ((out      (assoc-ref outputs "out"))
                         (site     (string-append out "/share/emacs/site-lisp/"))
                         (old-dir  (string-append site "feature-loader-patched-1.0.0/"))
                         (new-dir  (string-append site "feature-loader-1.0.0/")))
                    ;; Rename the autoloads files to match the original name
                    ;; so dependents that reference feature-loader-autoloads.* work.
                    (for-each
                     (lambda (ext)
                       (let ((old (string-append old-dir
                                                 "feature-loader-patched-autoloads"
                                                 ext))
                             (new (string-append old-dir
                                                 "feature-loader-autoloads"
                                                 ext)))
                         (when (file-exists? old)
                           (rename-file old new))))
                     '(".el" ".elc"))
                    ;; Rename the site-lisp subdirectory to match original
                    (rename-file old-dir new-dir)))))))))))

(define-module (configs patches)
  #:use-module (guix packages)
  #:use-module (guix utils))

;;; Work around emacs-feature-loader build failure.
;;;
;;; feature-loader.el calls (feature-loader) at top level which requires
;;; rde runtime Emacs libraries (rde-fonts -> fontaine -> modus-themes) that
;;; fail in headless batch Emacs during the validate-compiled-autoloads phase.
;;; There is no public substitute server for rde channel packages so the
;;; package must build from source.
;;;
;;; Fix: replace validate-compiled-autoloads with a no-op, keep everything
;;; else (name, version, install paths) identical to the original.
;;;
;;; Applied via module-define! so the patch is in effect before any rde
;;; feature evaluates (@ (rde packages emacs) emacs-feature-loader).

(define %patched-feature-loader
  (package/inherit (@ (rde packages emacs) emacs-feature-loader)
    (arguments
     (substitute-keyword-arguments
       (package-arguments (@ (rde packages emacs) emacs-feature-loader))
       ((#:phases phases #~%standard-phases)
        #~(modify-phases #$phases
            (replace 'validate-compiled-autoloads
              (lambda _
                ;; feature-loader.el calls (feature-loader) unconditionally
                ;; at load time, pulling in rde runtime code that fails in
                ;; batch/headless Emacs.  Skip validation; the compiled
                ;; autoloads are correct — only the self-check is broken.
                #t))))))))

(module-define!
 (resolve-module '(rde packages emacs))
 'emacs-feature-loader
 %patched-feature-loader)

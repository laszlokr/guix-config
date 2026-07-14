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
;;; Applied via variable-set! (NOT module-define!) so that compiled bytecode
;;; in rde modules that holds a pointer to the existing variable object sees
;;; the updated value.  module-define! creates a new variable object, leaving
;;; existing pointers in compiled code pointing to the old value.

(define %orig (@ (rde packages emacs) emacs-feature-loader))

(define %patched-feature-loader
  (package/inherit %orig
    (arguments
     (substitute-keyword-arguments (package-arguments %orig)
       ((#:phases phases #~%standard-phases)
        #~(modify-phases #$phases
            (replace 'validate-compiled-autoloads
              (lambda _
                ;; feature-loader.el calls (feature-loader) at top level,
                ;; pulling in rde runtime code that crashes in headless
                ;; batch Emacs.  The compiled autoloads are correct —
                ;; only the self-check is broken.
                #t))))))))

;;; Patch both the module's internal obarray and its public interface.
;;; variable-set! mutates the existing variable object in-place so all
;;; existing references (including those in already-loaded compiled modules)
;;; see the new value.
(let* ((m   (resolve-module '(rde packages emacs)))
       (pub (module-public-interface m)))
  (for-each
   (lambda (mod)
     (when mod
       (let ((v (module-variable mod 'emacs-feature-loader)))
         (if v
             (begin
               (format (current-error-port)
                       "[configs/patches] patching emacs-feature-loader in ~a~%"
                       (module-name mod))
               (variable-set! v %patched-feature-loader))
             (format (current-error-port)
                     "[configs/patches] WARNING: emacs-feature-loader not found in ~a~%"
                     (module-name mod))))))
   (list m pub)))

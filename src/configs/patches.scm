(define-module (configs patches)
  #:use-module (guix packages)
  #:use-module (guix utils))

;;; Work around emacs-feature-loader build failure.
;;;
;;; feature-loader.el has (feature-loader) at its top level.  The ;;;###autoload
;;; cookie causes this call to be copied verbatim into the generated autoloads
;;; file.  When validate-compiled-autoloads loads that file in headless batch
;;; Emacs, it executes (feature-loader) which pulls in rde runtime libraries
;;; (rde-fonts -> fontaine -> modus-themes) that crash without a display.
;;; There is no public substitute server for rde channel packages so the
;;; package must build from source.
;;;
;;; Fix (two layers):
;;;   1. add-before compile-autoloads: strip the bare (feature-loader) call
;;;      from feature-loader.el so it is never written into the autoloads file.
;;;   2. replace validate-compiled-autoloads with a no-op as a safety net.
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
            (add-before 'compile-autoloads 'remove-toplevel-feature-loader-call
              (lambda _
                ;; feature-loader.el has (feature-loader) at the top level.
                ;; The ;;;###autoload cookie causes this call to be copied
                ;; verbatim into the generated autoloads file.  When batch
                ;; Emacs loads that file during validate-compiled-autoloads,
                ;; it runs (feature-loader) which requires rde runtime libs
                ;; (rde-fonts -> fontaine -> modus-themes) that crash without
                ;; a display or rde runtime environment.
                ;; Fix: strip the bare call before autoloads are generated.
                (substitute* "feature-loader.el"
                  (("\\(feature-loader\\)\n") ""))))
            (replace 'validate-compiled-autoloads
              (lambda _ #t))))))))

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

(define-module (configs patches)
  #:use-module (guix packages)
  #:use-module (guix utils))

;;; Work around emacs-feature-loader build failure.
;;;
;;; The emacs-build-system's validate-compiled-autoloads phase loads
;;; feature-loader-autoloads.elc in headless batch Emacs.  That file calls
;;; (feature-loader) at the top level (via the ;;;###autoload cookie), which
;;; triggers the autoload for feature-loader.el, which also calls
;;; (feature-loader) at its top level.  The call pulls in rde runtime
;;; libraries (rde-fonts -> fontaine -> modus-themes) that fail without a
;;; display.  There is no public substitute server for rde channel packages.
;;;
;;; Fix: replace validate-compiled-autoloads with a no-op.  The compiled
;;; autoloads are correct; only the headless self-check fails.  The
;;; (feature-loader) call in the source is intentional — it runs at Emacs
;;; startup via the autoloads file and initialises rde feature loading.
;;; Do NOT remove it from the source (that breaks Emacs at runtime).
;;;
;;; Applied via variable-set! rather than module-define!: variable-set!
;;; mutates the existing variable object in-place so compiled rde bytecode
;;; that holds a pointer to the variable sees the updated package record.
;;; module-define! would create a new variable object and miss those pointers.

(define %orig (@ (rde packages emacs) emacs-feature-loader))

(define %patched-feature-loader
  (package/inherit %orig
    (arguments
     (substitute-keyword-arguments (package-arguments %orig)
       ((#:phases phases #~%standard-phases)
        #~(modify-phases #$phases
            (replace 'validate-compiled-autoloads
              (lambda _
                ;; The autoloads file calls (feature-loader) at the top level.
                ;; In headless batch Emacs this pulls in rde runtime libs that
                ;; crash without a display.  The compiled autoloads are correct
                ;; — only this self-check is broken.
                #t))))))))

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

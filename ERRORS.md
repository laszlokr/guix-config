First I encounter:
-*- mode: compilation; default-directory: "~/guix-config/" -*-
Compilation started at Wed May 13 00:51:35

make -k box/system/build
RDE_TARGET=box-system ./pre-inst-env target/profiles/guix/bin/guix system \
build ./src/configs/configs.scm
configs/hosts/mintsystem.scm:18:12: error: (uuid "TODO-fill-in-luks-uuid" (quote dce)): invalid UUID
make: *** [Makefile:41: box/system/build] Error 1

Compilation exited abnormally with code 2 at Wed May 13 00:51:36

And commented #:use-module (configs hosts mintsystem) in configs.scm until it's prepared.

But now I get another error:
-*- mode: compilation; default-directory: "~/guix-config/" -*-
Compilation started at Wed May 13 00:53:32

make -k box/system/build
RDE_TARGET=box-system ./pre-inst-env target/profiles/guix/bin/guix system \
build ./src/configs/configs.scm
guix system: warning: ambiguous package specification `emacs-guix'
guix system: warning: choosing emacs-guix@0.6.1 from gnu/packages/emacs-xyz.scm:8336:2
guix system: warning: ambiguous package specification `emacs-guix'
guix system: warning: choosing emacs-guix@0.6.1 from gnu/packages/emacs-xyz.scm:8336:2
guix system: warning: 'default-substitute-urls' in feature-base-services is deprecated and ignored, use 'guix-extensions' instead
guix system: warning: 'guix-authorized-keys' in feature-base-services is deprecated and ignored, use 'guix-extensions' instead
ice-9/eval.scm:223:20: In procedure proc:
error: %box-features: unbound variable
hint: Did you forget `(use-modules (configs hosts box))' or `#:use-module
(configs hosts box)'?

make: *** [Makefile:41: box/system/build] Error 1

Compilation exited abnormally with code 2 at Wed May 13 00:53:33

After latest git pull and compilation, the error is:
-*- mode: compilation; default-directory: "~/guix-config/" -*-
Compilation started at Wed May 13 01:10:44

make -k box/system/build
RDE_TARGET=box-system ./pre-inst-env target/profiles/guix/bin/guix system \
build ./src/configs/configs.scm
guix system: warning: ambiguous package specification `emacs-guix'
guix system: warning: choosing emacs-guix@0.6.1 from gnu/packages/emacs-xyz.scm:8336:2
guix system: warning: ambiguous package specification `emacs-guix'
guix system: warning: choosing emacs-guix@0.6.1 from gnu/packages/emacs-xyz.scm:8336:2
guix system: warning: 'default-substitute-urls' in feature-base-services is deprecated and ignored, use 'guix-extensions' instead
guix system: warning: 'guix-authorized-keys' in feature-base-services is deprecated and ignored, use 'guix-extensions' instead
ice-9/eval.scm:223:20: In procedure proc:
error: %box-features: unbound variable
hint: Did you forget `(use-modules (configs hosts box))' or `#:use-module
(configs hosts box)'?

make: *** [Makefile:41: box/system/build] Error 1

Compilation exited abnormally with code 2 at Wed May 13 01:10:44

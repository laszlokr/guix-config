# channels-lock.scm: channels.scm
# 	guix time-machine -C channels.scm -- \
# 	describe -f channels > tmp.scm
# 	mv tmp.scm channels-lock.scm

# home/build: channels-lock.scm
# 	RDE_TARGET=proto-home guix time-machine -C channels-lock.scm -- \
# 	home build -L ./src ~/.config/guix/src/laszlo/configs.scm


# profiles.mk provides guix version specified by rde/channels-lock.scm
# To rebuild channels-lock.scm use `make -B rde/channels-lock.scm`
include profiles.mk

# Also defined in .envrc to make proper guix version available project-wide
GUIX_PROFILE=target/profiles/guix
GUIX=./pre-inst-env ${GUIX_PROFILE}/bin/guix

SRC_DIR=./src
CONFIGS=${SRC_DIR}/configs/configs.scm
# LOAD_PATH_FLAGS=-L $(CURDIR)/src
PULL_EXTRA_OPTIONS=
# --allow-downgrades

ROOT_MOUNT_POINT=/mnt

VERSION=latest

SUBSTITUTE_URLS=--substitute-urls='https://bordeaux.guix.gnu.org https://substitutes.nonguix.org'

repl:
	${GUIX} repl -L ../tests \
	-L ../files/emacs/gider/src --listen=tcp:37146

box/home/build: guix
	RDE_TARGET=box-home ${GUIX} home \
	--fallback \
	--no-substitutes \
	build ${CONFIGS}

box/home/reconfigure: guix
	GUILE_AUTO_COMPILE=0 RDE_TARGET=box-home ${GUIX} home \
	--fallback \
	--no-substitutes \
	reconfigure ${CONFIGS}

box/system/build: guix
	RDE_TARGET=box-system ${GUIX} system \
	${SUBSTITUTE_URLS} \
	${LOAD_PATH_FLAGS} \
	build ${CONFIGS}

box/system/reconfigure: guix
	GUILE_AUTO_COMPILE=0 RDE_TARGET=box-system ${GUIX} system \
	${SUBSTITUTE_URLS} \
	${LOAD_PATH_FLAGS} \
	--fallback \
	--no-bootloader \
	reconfigure ${CONFIGS}

# Re-install the GRUB *binary* with cryptodisk support.
#
# IMPORTANT, and not what the old comment here implied: this does NOT update
# the boot menu.  guix's install-bootloader step does two things --
# install-boot-config, which writes /boot/grub/grub.cfg (the menu entries),
# and the bootloader installer, which writes the EFI binary.  --no-bootloader
# on box/system/reconfigure skips *both*; this target only ever did the
# second.  So running this alone leaves the menu as stale as it was, still
# booting whatever generation grub.cfg last recorded.  See
# doc/box-bootloader.md for the sequence that actually refreshes the menu.
#
# Needs root, and needs /boot/efi mounted.
#
# --removable matches box's configured grub-efi-removable-bootloader, whose
# installer passes it too; without it grub-install writes EFI/Guix plus an
# NVRAM entry rather than the EFI/BOOT/BOOTX64.EFI path the firmware boots.
#
# NOTE the $$(...): inside a recipe, a single $( ) is expanded by *make*, not
# the shell.  This target originally used $(find ...), which make expanded to
# the empty string -- so the recipe began with "--target=x86_64-efi" and died
# with "command not found" every single time.  It had therefore never once
# succeeded since being added in commit 7b74d0b.
box/system/install-bootloader:
	@set -e; \
	grub_install=$$(ls -d /gnu/store/*-grub-efi-*/sbin/grub-install 2>/dev/null | tail -1); \
	if [ -z "$$grub_install" ]; then \
	  echo "error: no grub-efi grub-install found in /gnu/store" >&2; exit 1; \
	fi; \
	echo "using $$grub_install"; \
	GRUB_ENABLE_CRYPTODISK=y "$$grub_install" \
	  --target=x86_64-efi \
	  --efi-directory=/boot/efi \
	  --bootloader-id=Guix \
	  --removable \
	  --modules="cryptodisk luks2 gcry_rijndael gcry_sha256 ext2 part_gpt" \
	  /dev/nvme0n1

# reform — MNT Reform, Banana Pi CM4 module (Amlogic A311D, aarch64).
#
# Targets are split by the machine they run on: the first group runs on the
# Reform itself, the second on the x86_64 box to prebuild for it.  See
# doc/reform-build-box.md (serving) and doc/reform-install.md (installing).
#
# Building on the Reform is viable because the MNT Reform kernel is fully
# substitutable -- the thing it does not have the RAM for never happens.  The
# box is worth having for the rest of the closure, not for the kernel.
#
# NOTE: cross-built (--target=) and natively-built (--system=) store items are
# *different derivations*.  Only --system=aarch64-linux output can be served as
# substitutes to the Reform.  The cross target is a structural check of the
# config only -- it does not build to completion (libgudev fails to
# cross-compile; see doc/reform-build-box.md).
#
# NOTE: `guix home' takes neither --system nor --target (unlike `guix system'
# and `guix pull', which take --system).  So the Reform's home environment can
# only be built on the Reform; there is no reform/home box-side target.
REFORM_CROSS=--target=aarch64-linux-gnu
REFORM_EMULATED=--system=aarch64-linux

# Substitute servers for the Reform.  Put the box first so it is preferred;
# override on the command line until it is actually publishing, e.g.
#   make reform/system/build REFORM_SUBSTITUTE_URLS=
REFORM_SUBSTITUTE_URLS=--substitute-urls='https://bordeaux.guix.gnu.org https://ci.guix.gnu.org'

# Extra flags for a single invocation, e.g.
#   make reform/system/init REFORM_EXTRA_OPTIONS=--skip-checks
REFORM_EXTRA_OPTIONS=


## Targets to run ON THE REFORM (native aarch64 -- no --system, no --target)
#
# These are safe to run on the A311D: the MNT Reform kernel is fully
# substitutable, so nothing here compiles a kernel.  What is built locally is
# this host's own service glue -- shepherd .go files, etc, activation scripts
# -- which is Guile compilation, not a 4 GB-RAM problem.
#
# Check that before committing to a build.  If dry-run says the kernel
# "would be built" rather than "would be downloaded", stop and fix
# substitutes first; that build will not fit on this machine.

reform/system/dry-run: guix
	RDE_TARGET=reform-system ${GUIX} system \
	${REFORM_SUBSTITUTE_URLS} \
	${LOAD_PATH_FLAGS} \
	${REFORM_EXTRA_OPTIONS} \
	build --dry-run ${CONFIGS}

reform/system/build: guix
	RDE_TARGET=reform-system ${GUIX} system \
	${REFORM_SUBSTITUTE_URLS} \
	${LOAD_PATH_FLAGS} \
	${REFORM_EXTRA_OPTIONS} \
	build ${CONFIGS}

# Installs onto the NVMe mounted at ${ROOT_MOUNT_POINT}, from the running
# Debian.  Do NOT `make cow-store' first -- that is for installer media; see
# doc/reform-install.md.  Fill in the real root UUID in hosts/reform.scm
# before this: `guix system init' refuses to install an unresolvable one.
reform/system/init: guix
	sudo RDE_TARGET=reform-system ${GUIX} system \
	${REFORM_SUBSTITUTE_URLS} \
	${LOAD_PATH_FLAGS} \
	${REFORM_EXTRA_OPTIONS} \
	init ${CONFIGS} ${ROOT_MOUNT_POINT}

# After the NVMe system is booted.
reform/system/reconfigure: guix
	sudo RDE_TARGET=reform-system ${GUIX} system \
	${REFORM_SUBSTITUTE_URLS} \
	${LOAD_PATH_FLAGS} \
	${REFORM_EXTRA_OPTIONS} \
	reconfigure ${CONFIGS}

reform/home/build: guix
	RDE_TARGET=reform-home ${GUIX} home \
	${REFORM_SUBSTITUTE_URLS} \
	build ${CONFIGS}

reform/home/reconfigure: guix
	RDE_TARGET=reform-home ${GUIX} home \
	${REFORM_SUBSTITUTE_URLS} \
	reconfigure ${CONFIGS}


## Targets to run ON THE BOX (x86_64), to prebuild for the Reform

# Structural check of the config only.  Does not build to completion --
# libgudev fails to cross-compile; see doc/reform-build-box.md.
reform/system/cross-dry-run: guix
	RDE_TARGET=reform-system ${GUIX} system \
	${SUBSTITUTE_URLS} \
	${LOAD_PATH_FLAGS} \
	${REFORM_CROSS} \
	build --dry-run ${CONFIGS}

reform/system/cross-build: guix
	RDE_TARGET=reform-system ${GUIX} system \
	${SUBSTITUTE_URLS} \
	${LOAD_PATH_FLAGS} \
	${REFORM_CROSS} \
	build ${CONFIGS}

# Requires qemu-binfmt for aarch64 on the box.  Produces exactly the store
# items the Reform asks for, so `guix publish' can serve them.  --cores=1 is
# deliberate: the man-db hook segfaults under parallel qemu-user emulation.
reform/system/emulated-build: guix
	RDE_TARGET=reform-system ${GUIX} system \
	${SUBSTITUTE_URLS} \
	${LOAD_PATH_FLAGS} \
	${REFORM_EMULATED} \
	--cores=1 \
	build ${CONFIGS}

reform/weather: guix
	${GUIX} weather ${REFORM_EMULATED} \
	linux-libre-arm64-mnt-reform linux-firmware

mintsystem/home/build: guix
	RDE_TARGET=mintsystem-home ${GUIX} home \
	build ${CONFIGS}

mintsystem/home/reconfigure: guix
	RDE_TARGET=mintsystem-home ${GUIX} home \
	reconfigure ${CONFIGS}

cow-store:
	sudo herd start cow-store ${ROOT_MOUNT_POINT}

target:
	mkdir -p target

target/release:
	mkdir -p target/release

# TODO: Prevent is rebuilds.
release/rde-live-x86_64: target/rde-live.iso target/release
	cp -df $< target/release/rde-live-${VERSION}-x86_64.iso
	gpg -ab target/release/rde-live-${VERSION}-x86_64.iso

minimal-emacs: guix
	${GUIX} shell --pure -Df ./src/configs/minimal-emacs.scm \
	-E '.*GTK.*|.*XDG.*|.*DISPLAY.*' \
	--rebuild-cache -- emacs -q \
	--eval "(load \"~/.config/emacs/early-init.el\")"
	#--eval "(require 'feature-loader-portable)"

minimal/home/build: guix
	${GUIX} home build ./src/configs/minimal.scm

clean-target:
	rm -rf ./target

clean: clean-target

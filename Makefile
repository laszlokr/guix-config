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

# Run this once after manual grub-install recovery, or after kernel changes.
# Requires: cryptsetup open /dev/nvme0n1p2 cryptroot (already done at runtime)
box/system/install-bootloader: guix
	$(find /gnu/store -name "grub-install" | grep "2\.12" | grep sbin | head -1) \
	--target=x86_64-efi \
	--efi-directory=/boot/efi \
	--bootloader-id=Guix \
	--modules="cryptodisk luks2 gcry_rijndael gcry_sha256 ext2 part_gpt" \
	/dev/nvme0n1

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

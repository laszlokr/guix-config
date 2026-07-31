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
	${SUBSTITUTE_URLS} \
	--fallback \
	build ${CONFIGS}

box/home/reconfigure: guix
	RDE_TARGET=box-home ${GUIX} home \
	${SUBSTITUTE_URLS} \
	--fallback \
	reconfigure ${CONFIGS}

box/system/build: guix
	RDE_TARGET=box-system ${GUIX} system \
	${SUBSTITUTE_URLS} \
	build ${CONFIGS}

box/system/reconfigure: guix
	RDE_TARGET=box-system ${GUIX} system \
	${SUBSTITUTE_URLS} \
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

# reform — MNT Reform (full-size) with Banana Pi CM4 / A311D, aarch64.
#
# Needs lykso's checkout on the load path: (mnt-reform a311d) supplies the
# kernel carrying meson-g12b-bananapi-cm4-mnt-reform2.dts, which upstream guix
# does not have.  It is NOT usable as a channel (its .guix-channel points at
# .guix/modules, which does not exist in the repo), so clone it and set:
#
#     git clone https://codeberg.org/lykso/mnt-reform-nonguix
#     make reform/system/build LYKSO_DIR=/path/to/mnt-reform-nonguix
#
# aarch64 from an x86_64 host needs --system (emulated) or --target (cross).
LYKSO_DIR=../mnt-reform-nonguix
REFORM_SYSTEM=aarch64-linux

reform/system/build: guix
	RDE_TARGET=reform-system ${GUIX} system \
	${SUBSTITUTE_URLS} \
	-L ${LYKSO_DIR} \
	--system=${REFORM_SYSTEM} \
	build ${CONFIGS}

# Check substitute availability before committing to a long kernel build.
reform/weather: guix
	${GUIX} weather \
	-L ${LYKSO_DIR} \
	--system=${REFORM_SYSTEM} \
	linux-mnt-reform-a311d-6.6

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

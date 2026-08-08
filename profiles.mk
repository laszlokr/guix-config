
#
# Profiles
#

# Store items doesn't have useful mtime, so we rely on guix.lock to prevent
# unecessary rebuilds
guix: target/guix-time-marker

target/profiles:
	mkdir -p target/profiles

target/guix-time-marker: rde/channels-lock.scm
	make target/profiles/guix
	touch $@

target/profiles/guix: target/profiles rde/channels-lock.scm
	guix pull -C rde/channels-lock.scm -p ${GUIX_PROFILE} \
	${PULL_EXTRA_OPTIONS}

target/profiles/guix-local: target/profiles rde/channels-lock-local.scm
	guix pull -C rde/channels-lock-local.scm -p ${GUIX_PROFILE} \
	${PULL_EXTRA_OPTIONS}

# NOTE: no "(use-modules (guix channels))" header.  guix evaluates channel
# files in an isolated sandbox exposing only %safe-channel-bindings (see
# %safe-channel-bindings in guix/scripts/pull.scm) -- `channel',
# `make-channel-introduction', `openpgp-fingerprint' and friends are
# pre-injected, and `use-modules' is deliberately NOT available.  Emitting
# that header makes every `guix pull -C' fail with
# "use-modules: unbound variable".
rde/channels-lock.scm: rde/channels.scm
	guix time-machine -C ./rde/channels.scm -- \
	describe -f channels > ./rde/channels-lock-tmp.scm
	mv ./rde/channels-lock-tmp.scm ./rde/channels-lock.scm

rde/channels-lock-local.scm: rde/channels-local.scm
	guix time-machine -C ./rde/channels-local.scm -- \
	describe -f channels > ./rde/channels-lock-tmp.scm
	mv ./rde/channels-lock-tmp.scm ./rde/channels-lock-local.scm

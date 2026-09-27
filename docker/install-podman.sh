#!/bin/sh
# Installs podman so a running sandbox session can build/run nested OCI
# containers. Not baked into the image by default: it adds ~100MB
# (podman itself is ~76MB, netavark ~18MB, plus fuse-overlayfs/slirp4netns/
# uidmap) that most sessions never use -- run this once, on demand, inside
# a session that actually needs it:
#
#   docker exec -u root <container> install-podman
#
# Whether `podman build`/`podman run` actually WORK afterwards depends on
# privileges the *sandbox* container itself was started with, not on
# anything this script can configure from inside:
#   - `podman build`/`run` need to create their own nested user+mount+net
#     namespaces. If the sandbox container's own root lacks CAP_SYS_ADMIN
#     (dropped by default outside `--privileged`), every RUN step in a
#     `podman build` fails to mount its own /proc, and `podman run`
#     containers fail the same way.
#   - This needs /etc/subuid and /etc/subgid entries for `root` that fall
#     within a range the sandbox container actually owns (check
#     `cat /proc/self/uid_map`), or podman falls back to a "single
#     mapping" that breaks multi-UID operations like unpacking a base
#     image layer (chown failures on files it doesn't own, e.g.
#     /etc/gshadow).
#   - /dev/fuse must be passed through to the sandbox container for
#     fuse-overlayfs (storage.conf below) to mount.
#
# In short: this script alone is not sufficient inside a container that
# was started without elevated privileges -- that has to be granted by
# whatever launches the sandbox container (e.g. `--privileged`, or
# `--cap-add SYS_ADMIN --device /dev/fuse` plus a subuid/subgid range for
# root). Verified against podman 5.7.0 on Ubuntu 26.04: even with a correct
# subuid range and fuse-overlayfs storage, `podman build` still failed on
# every RUN step with "mount proc to proc: Operation not permitted" (or,
# with crun, a fatal ping_group_range sysctl write against a read-only
# /proc/sys) when the sandbox container itself only had the default
# non-privileged capability set.
set -eu

apt-get update
apt-get install -y --no-install-recommends \
    podman \
    fuse-overlayfs \
    slirp4netns \
    uidmap
rm -rf /var/lib/apt/lists/*

mkdir -p /etc/containers/containers.conf.d
printf '%s\n' \
    '[storage]' \
    'driver = "overlay"' \
    '' \
    '[storage.options]' \
    'mount_program = "/usr/bin/fuse-overlayfs"' \
    > /etc/containers/storage.conf
printf '%s\n' \
    '[engine]' \
    'cgroup_manager = "cgroupfs"' \
    'events_logger = "file"' \
    > /etc/containers/containers.conf.d/sandbox.conf

echo "podman installed. If 'podman build'/'podman run' fail with mount or" >&2
echo "namespace errors, the sandbox container needs to be started with" >&2
echo "more privilege (CAP_SYS_ADMIN, /dev/fuse, a subuid/subgid range for" >&2
echo "root) -- see the comment at the top of this script." >&2

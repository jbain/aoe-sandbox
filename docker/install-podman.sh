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
# In short: in a default unprivileged sandbox, /proc/sys and /sys/fs/cgroup
# are read-only by design, and crun fails when it tries to write to them
# (ping_group_range sysctl, cgroup.subtree_control). Rather than make them
# writable, this script avoids the writes: when /sys/fs/cgroup is not
# writable it adds a drop-in (sandbox-restricted.conf below) that sets
# `cgroups = "disabled"` and `netns = "host"`. With that, `podman build` and
# `podman run` work (verified against podman 5.7.0, crun 1.21, Ubuntu 26.04
# arm64), at these costs:
#   - nested containers use host networking and have no cgroup resource
#     limits.
#   - nested containers share the sandbox's network namespace, so two of
#     them cannot bind the same port.
# In a `--privileged` sandbox the drop-in is skipped, so cgroup limits and
# network isolation stay in place. Other requirements (CAP_SYS_ADMIN,
# /dev/fuse, a subuid/subgid range for root) still have to be granted by
# whatever launches the sandbox container.
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

# Restricted sandbox: /sys/fs/cgroup (and /proc/sys) are read-only, so skip
# the cgroup and netns setup that would write to them.
restricted=false
if [ ! -w /sys/fs/cgroup ]; then
    restricted=true
    printf '%s\n' \
        '[containers]' \
        'cgroups = "disabled"' \
        'netns = "host"' \
        > /etc/containers/containers.conf.d/sandbox-restricted.conf
fi

echo "podman installed." >&2
if [ "$restricted" = true ]; then
    echo "Restricted sandbox detected (/sys/fs/cgroup is read-only): wrote" >&2
    echo "/etc/containers/containers.conf.d/sandbox-restricted.conf, so nested" >&2
    echo "containers run with cgroups disabled (no resource limits) and host" >&2
    echo "networking (they share this sandbox's network namespace, so two" >&2
    echo "containers cannot bind the same port)." >&2
fi
echo "If 'podman build'/'podman run' fail with mount or namespace errors," >&2
echo "the sandbox container needs to be started with more privilege" >&2
echo "(CAP_SYS_ADMIN, /dev/fuse, a subuid/subgid range for root) -- see the" >&2
echo "comment at the top of this script." >&2

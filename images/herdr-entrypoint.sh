#!/bin/sh
set -eu

user=${HOST_USER:?HOST_USER not set}

# Persistent host keys (volume), so clients don't see key changes on rebuild.
mkdir -p /etc/ssh/host-keys /run/sshd
for type in ed25519 rsa; do
  key=/etc/ssh/host-keys/ssh_host_${type}_key
  [ -f "$key" ] || ssh-keygen -q -t "$type" -N '' -f "$key"
done

# herdr-core puts its socket in $XDG_RUNTIME_DIR/herdr-core, falling back to
# /run/user/<uid>. Make that exist so SSH sessions and the core agree.
uid=$(id -u "$user")
install -d -m 700 -o "$user" -g "$(id -g "$user")" "/run/user/$uid"
export XDG_RUNTIME_DIR="/run/user/$uid"

# Start the core as the host user (never as root). Backgrounded so it works
# whether or not `hc server start` detaches; `hc` also starts one on demand.
runuser -u "$user" -- hc server start &

exec /usr/sbin/sshd -D -e

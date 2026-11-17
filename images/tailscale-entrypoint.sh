#!/bin/sh
set -eu

user=${HOST_USER:?HOST_USER not set}

# Relay keypair (volume): the private key stays in this container, the public
# key is published to herdr's sshd as its only authorized key, limited to
# loopback and with forwarding disabled.
key=/etc/herdr-relay/key/id_ed25519
[ -f "$key" ] || ssh-keygen -q -t ed25519 -N '' -C herdr-relay -f "$key"
chown "$user" "$key" "$key.pub"
chmod 600 "$key"

auth=/etc/herdr-relay/authorized-keys/authorized_keys
printf 'from="127.0.0.1,::1",restrict,pty %s\n' "$(cat "$key.pub")" > "$auth.tmp"
chmod 644 "$auth.tmp"
mv "$auth.tmp" "$auth"

exec /usr/local/bin/containerboot "$@"

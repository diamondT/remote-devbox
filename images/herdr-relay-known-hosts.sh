#!/bin/sh
# KnownHostsCommand for the relay: trust herdr's persistent sshd host keys
# (ssh-host-keys volume, mounted read-only) for 127.0.0.1.
for pub in /etc/herdr-relay/host-keys/ssh_host_*_key.pub; do
  [ -f "$pub" ] && printf '127.0.0.1 %s\n' "$(cut -d' ' -f1,2 "$pub")"
done
exit 0

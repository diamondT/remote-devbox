#!/bin/sh
# Login shell of $USER in the tailscale container. Tailscale SSH has already
# authenticated the tailnet user; this relays the session to sshd in the herdr
# container, which listens on 127.0.0.1 of the shared network namespace.
#
# Invoked as a login shell (no args, or -l) or with -c <command>.
has_cmd=false
cmd=
while [ $# -gt 0 ]; do
  case $1 in
    -c|-lc)
      [ $# -ge 2 ] || { echo "herdr-relay: -c needs a command" >&2; exit 2; }
      has_cmd=true; cmd=$2; shift 2 ;;
    *) shift ;;
  esac
done

if [ -t 0 ] && [ -t 1 ]; then tty=-t; else tty=-T; fi

set -- \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o IdentityFile=/etc/herdr-relay/key/id_ed25519 \
  -o KnownHostsCommand=/usr/local/bin/herdr-relay-known-hosts \
  -o UserKnownHostsFile=/dev/null \
  -o GlobalKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=yes \
  -o LogLevel=ERROR \
  "$tty"

if $has_cmd; then
  exec ssh "$@" 127.0.0.1 "$cmd"
else
  exec ssh "$@" 127.0.0.1
fi

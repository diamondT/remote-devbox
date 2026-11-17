#!/bin/sh
# Start a D-Bus session bus and an unlocked GNOME Keyring (Secret Service) for
# the current user, then exec "$@" if given. Tools like bb store their secrets
# there. Safe to run more than once: it only starts what isn't running yet.
#
# The keyring is unlocked with a fixed password. That only obfuscates the file
# at rest; it lives in a per-service volume, readable by whoever can reach the
# container anyway.
set -eu

: "${DBUS_SESSION_BUS_ADDRESS:?DBUS_SESSION_BUS_ADDRESS not set}"
password=container

has_owner() {
  dbus-send --session --print-reply --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner "string:$1" \
    2>/dev/null | grep -q 'boolean true'
}

# A bus socket left over from before a container restart refuses connections.
if ! has_owner org.freedesktop.DBus; then
  rm -f "${DBUS_SESSION_BUS_ADDRESS#unix:path=}"
  dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --fork --nopidfile
fi

if ! has_owner org.freedesktop.secrets; then
  # Creates the "login" keyring (the default collection) on first start.
  printf '%s' "$password" \
    | gnome-keyring-daemon --unlock --components=secrets >/dev/null
  # The daemon claims its bus name after forking; wait for it.
  i=0
  until has_owner org.freedesktop.secrets; do
    i=$((i + 1))
    [ "$i" -le 50 ] || { echo "keyring-start: keyring did not start" >&2; exit 1; }
    sleep 0.1
  done
fi

[ "$#" -eq 0 ] || exec "$@"

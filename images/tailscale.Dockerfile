# syntax=docker/dockerfile:1
# Tailscale node with Tailscale SSH. Sessions run here (tailscaled forks the
# shell), so $USER's login shell is a relay that hands the session to sshd in
# the herdr container over loopback (shared network namespace).
# Like the other images, nothing is pinned: compose builds with pull + no_cache.
FROM docker.io/tailscale/tailscale:latest
ARG USERNAME
ARG USER_UID=1000
ARG USER_GID=1000
ARG USER_HOME

RUN apk add --no-cache openssh-client

COPY herdr-relay.sh /usr/local/bin/herdr-relay
COPY herdr-relay-known-hosts.sh /usr/local/bin/herdr-relay-known-hosts
COPY tailscale-entrypoint.sh /usr/local/bin/tailscale-entrypoint.sh
RUN chmod 755 /usr/local/bin/herdr-relay /usr/local/bin/herdr-relay-known-hosts \
      /usr/local/bin/tailscale-entrypoint.sh \
 && echo /usr/local/bin/herdr-relay >> /etc/shells

# Same name/uid/gid/home as the host user, so Tailscale SSH can log in as $USER.
RUN test -n "$USERNAME" && test -n "$USER_HOME" \
 && group=$(awk -F: -v g="$USER_GID" '$3 == g { print $1 }' /etc/group) \
 && if [ -z "$group" ]; then addgroup -g "$USER_GID" "$USERNAME" && group=$USERNAME; fi \
 && mkdir -p "$(dirname "$USER_HOME")" \
 && adduser -D -u "$USER_UID" -G "$group" -h "$USER_HOME" \
      -s /usr/local/bin/herdr-relay "$USERNAME"

ENV HOST_USER=${USERNAME}
ENTRYPOINT ["/usr/local/bin/tailscale-entrypoint.sh"]

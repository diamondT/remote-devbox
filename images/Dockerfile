# syntax=docker/dockerfile:1
# One Dockerfile, three targets (claude, herdr, t3) sharing a common base.
# Nothing is pinned: compose builds with pull + no_cache, so every rebuild
# fetches the latest base image, Claude Code and herdr-core.
#
# The image mirrors the host user (name, uid/gid, home path), so the host's
# ~/.claude, ~/.t3, herdr state and project dirs can be bind-mounted at the
# same absolute paths and keep working on both sides.

# ---------------------------------------------------------------- base
FROM docker.io/oven/bun:debian AS base
ARG USERNAME
ARG USER_UID=1000
ARG USER_GID=1000
ARG USER_HOME

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client ripgrep procps less tini \
 && rm -rf /var/lib/apt/lists/*

# Replace the image's "bun" (uid 1000) account with the host user. The dirs
# that get bind-mounted into are pre-created so their parents aren't root-owned.
RUN test -n "$USERNAME" && test -n "$USER_HOME" \
 && userdel -r bun \
 && { getent group "$USER_GID" >/dev/null || groupadd -g "$USER_GID" "$USERNAME"; } \
 && useradd -u "$USER_UID" -g "$USER_GID" -d "$USER_HOME" -m -s /bin/bash "$USERNAME" \
 && mkdir -p "$USER_HOME/.claude" "$USER_HOME/.config" "$USER_HOME/.local/state" \
      "$USER_HOME/.ssh" \
 && chmod 700 "$USER_HOME/.ssh" \
 && chown -R "$USER_UID:$USER_GID" "$USER_HOME"

ENV HOST_USER=${USERNAME}
WORKDIR ${USER_HOME}
ENTRYPOINT ["/usr/bin/tini", "--"]

# ---------------------------------------------------------------- claude
FROM base AS claude
ARG USER_UID=1000
ARG USER_GID=1000
ARG USER_HOME
# Native installer (the npm package needs a postinstall step bun won't run).
# Installs to ~/.local/bin/claude, the same path as a native install on the host.
USER ${USER_UID}:${USER_GID}
RUN curl -fsSL https://claude.ai/install.sh | bash -s latest
USER root
RUN ln -s "$USER_HOME/.local/bin/claude" /usr/local/bin/claude
# Updates would land in the image layer, not on the host; rebuild to update.
ENV DISABLE_AUTOUPDATER=1
USER ${USER_UID}:${USER_GID}
CMD ["sleep", "infinity"]

# ---------------------------------------------------------------- t3 (server)
FROM claude AS t3
ARG USER_UID=1000
ARG USER_GID=1000
USER root
# `t3` = bunx launcher for the latest release. It fetches the matching T3
# server binary into ~/.t3/runtime (the host's ~/.t3) when the version changes.
RUN printf '%s\n' '#!/bin/sh' 'exec bunx --bun t3@latest "$@"' \
      > /usr/local/bin/t3 \
 && chmod 755 /usr/local/bin/t3
ENV T3CODE_HOST=0.0.0.0 \
    T3CODE_PORT=3773 \
    T3CODE_NO_BROWSER=true \
    T3CODE_SERVER_BROWSER_SANDBOX=0
USER ${USER_UID}:${USER_GID}
CMD ["t3", "serve"]

# ---------------------------------------------------------------- herdr-core
FROM claude AS herdr
ARG USERNAME
ARG USER_UID=1000
USER root
# Password "*" = none set, but not "locked", so key-only SSH login works.
# zsh is the login shell (SSH sessions, and herdr-core panes via $SHELL). The
# host's ~/.zshrc is bind-mounted read-only (see compose.yaml); starship, eza
# and bat (installed as batcat) are tools it uses.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-server zsh starship eza bat \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/ssh/ssh_host_* \
 && curl -fsSL https://releases.herdr.dev/core/install.sh \
      | HC_INSTALL_DIR=/usr/local/bin sh \
 && usermod -p '*' -s /usr/bin/zsh "$USERNAME"
ENV SHELL=/usr/bin/zsh

# SSH sessions start with a clean environment; pam_env loads this file.
RUN printf '%s\n' \
      'DISABLE_AUTOUPDATER=1' \
      "XDG_RUNTIME_DIR=/run/user/${USER_UID}" \
      >> /etc/environment

COPY sshd_config /etc/ssh/sshd_config.d/10-remote-dev.conf
COPY herdr-entrypoint.sh /usr/local/bin/herdr-entrypoint.sh
RUN chmod 755 /usr/local/bin/herdr-entrypoint.sh

# Runs as root only to start sshd; herdr-core itself runs as the host user.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/herdr-entrypoint.sh"]
CMD []

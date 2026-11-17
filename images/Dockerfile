# syntax=docker/dockerfile:1
# One Dockerfile, three targets (claude, herdr, t3) sharing a common base.
# Nothing is pinned: compose builds with pull + no_cache, so every rebuild
# fetches the latest base image, Claude Code, herdr-core and acli.
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

# python3 and jq: Claude Code plugin hooks from the host's ~/.claude need them
# (e.g. remember's PostToolUse hook exits 1 without a Python >= 3.9).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client ripgrep procps less tini \
      python3 jq \
 && rm -rf /var/lib/apt/lists/*

# Atlassian CLI (acli): latest release binary for the build architecture.
RUN arch=$(dpkg --print-architecture) \
 && curl -fsSL -o /usr/local/bin/acli \
      "https://acli.atlassian.com/linux/latest/acli_linux_${arch}/acli" \
 && chmod 755 /usr/local/bin/acli

# bb (Bitbucket CLI): a copy of the host's ~/.cargo/bin/bb (the "cargo-bin"
# build context in compose.yaml), so rebuild after updating it on the host.
# It keeps its secrets in the Secret Service, so each container runs its own
# D-Bus session bus and an unlocked GNOME Keyring (see keyring-start.sh).
# dbus-x11 provides the session bus without pulling in systemd.
RUN apt-get update \
 && apt-get install -y --no-install-recommends dbus-x11 gnome-keyring \
 && rm -rf /var/lib/apt/lists/*
COPY --from=cargo-bin bb /usr/local/bin/bb
COPY keyring-start.sh /usr/local/bin/keyring-start
RUN chmod 755 /usr/local/bin/bb /usr/local/bin/keyring-start

# Replace the image's "bun" (uid 1000) account with the host user. The dirs
# that get bind-mounted into are pre-created so their parents aren't root-owned.
RUN test -n "$USERNAME" && test -n "$USER_HOME" \
 && userdel -r bun \
 && { getent group "$USER_GID" >/dev/null || groupadd -g "$USER_GID" "$USERNAME"; } \
 && useradd -u "$USER_UID" -g "$USER_GID" -d "$USER_HOME" -m -s /bin/bash "$USERNAME" \
 && mkdir -p "$USER_HOME/.claude" "$USER_HOME/.config" "$USER_HOME/.local/state" \
      "$USER_HOME/.ssh" "$USER_HOME/.m2" \
      "$USER_HOME/.config/bb" "$USER_HOME/.local/share/keyrings" \
 && chmod 700 "$USER_HOME/.ssh" \
 && chown -R "$USER_UID:$USER_GID" "$USER_HOME" \
 && install -d -m 700 -o "$USER_UID" -g "$USER_GID" "/run/user/$USER_UID"

ENV HOST_USER=${USERNAME} \
    XDG_RUNTIME_DIR=/run/user/${USER_UID} \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${USER_UID}/bus
WORKDIR ${USER_HOME}
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/keyring-start"]

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

# Java: Debian's OpenJDK 25 is the system default, so java is on PATH in every
# session. The host's ~/.jdks is also mounted read-only (see compose.yaml), so
# the JAVA_HOME the host's ~/.zshrc sets, and its JDK-switching aliases,
# resolve in interactive shells too.
# Maven: the newest 4.x on Maven Central (pre-releases included, as 4 has no
# final release yet), checked against its published SHA-512.
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-25-jdk-headless \
 && rm -rf /var/lib/apt/lists/* \
 && base=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven \
 && v=$(curl -fsSL "$base/maven-metadata.xml" \
        | sed -n 's|.*<version>\(4\.[^<]*\)</version>.*|\1|p' | tail -n 1) \
 && test -n "$v" \
 && curl -fsSL -o /tmp/maven.tar.gz "$base/$v/apache-maven-$v-bin.tar.gz" \
 && sha=$(curl -fsSL "$base/$v/apache-maven-$v-bin.tar.gz.sha512" | cut -d' ' -f1) \
 && echo "$sha  /tmp/maven.tar.gz" | sha512sum -c - \
 && mkdir /opt/maven \
 && tar -xzf /tmp/maven.tar.gz -C /opt/maven --strip-components=1 \
 && rm /tmp/maven.tar.gz \
 && ln -s /opt/maven/bin/mvn /usr/local/bin/mvn

# SSH sessions start with a clean environment; pam_env loads this file.
RUN printf '%s\n' \
      'DISABLE_AUTOUPDATER=1' \
      "XDG_RUNTIME_DIR=/run/user/${USER_UID}" \
      "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${USER_UID}/bus" \
      >> /etc/environment

COPY sshd_config /etc/ssh/sshd_config.d/10-remote-dev.conf
COPY herdr-entrypoint.sh /usr/local/bin/herdr-entrypoint.sh
RUN chmod 755 /usr/local/bin/herdr-entrypoint.sh

# Runs as root only to start sshd; herdr-core itself runs as the host user.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/herdr-entrypoint.sh"]
CMD []

# remote-dev

Exposes an existing dev machine's Claude Code, herdr-core and T3 server
state through Tailscale, without running Tailscale on the host. Deploy on the
remote machine and run it only while nobody is working there. The containers
use the same files as the desktop apps, so stop one side before starting the
other.

| service     | what                                   | reach it                                            |
|-------------|----------------------------------------|-----------------------------------------------------|
| `tailscale` | tailnet node; owns the network namespace | —                                                  |
| `claude`    | Claude Code CLI                        | `docker compose exec claude claude`                 |
| `herdr`     | herdr-core (`hc`) + sshd + Claude Code | `ssh $USER@<TS_HOSTNAME>` / `hc machine add $USER@<TS_HOSTNAME> --name box` |
| `t3`        | T3 server (`t3 serve` via `bunx`, headless) | `http://<TS_HOSTNAME>:3773` on the tailnet      |

`claude`, `herdr` and `t3` use `network_mode: service:tailscale`, so all their
traffic goes through the tailscale container's network stack. If you set
`TS_EXIT_NODE`, all their internet egress also goes through that exit node.
Name resolution still uses the engine's DNS.

## Shared with the host

The images are built for the user who runs compose: same name, uid/gid and
home path. Those come from `$USER`, `$HOME` and `HOST_UID`/`HOST_GID`. Host
dirs are mounted at the same absolute paths:

| host path                    | mounted in       |
|------------------------------|------------------|
| `$WORK_DIR` (`~/dev`)        | claude, herdr, t3 |
| `~/.claude`                  | claude, herdr, t3 |
| `~/.gitconfig`, `~/.config/git` (ro) | claude, herdr, t3 |
| `~/.local/state/herdr-core`  | herdr            |
| `~/.t3`                      | t3               |
| `~/.ssh/authorized_keys` (ro, as sshd's key file for `$USER`) | herdr |

All of these must exist on the host. Docker creates a missing source as a
root-owned directory.

## Setup

```sh
cp .env.example .env            # TS_AUTHKEY, HOST_UID/HOST_GID, WORK_DIR if not ~/dev

hc server stop                  # stop the host side first (and quit the T3 / Claude apps)
docker compose up -d --build    # or: podman compose up -d --build (USERNS_MODE=keep-id)

docker compose exec t3 t3 pair  # pairing link for the T3 server
```

## Notes

- Images are based on `oven/bun` (Debian). `t3` inside the t3 container is a
  wrapper around `bunx --bun t3@latest`. It reuses or downloads the T3
  server binary in `~/.t3/runtime`. Claude Code uses its native installer: the
  npm package needs a postinstall step that bun skips by default.
- Nothing is pinned. Builds always pull the base image and skip the layer
  cache (`pull` / `no_cache` in compose.yaml), so every rebuild fetches the
  latest Bun, Claude Code and herdr-core. The tailscale image has
  `pull_policy: always`, so it is pulled on every `up`. The Claude auto-updater
  is off, so rebuild to update.
- The image is tied to one user. Rebuild if you deploy for a different user or
  uid.
- herdr-core has no TCP API, only a Unix socket. Remote clients reach it over
  SSH (port 22 on the tailnet IP). Tailscale SSH is not enabled, so that port
  is free for sshd. Running terminals don't move between host and container.
  Each side's core starts its own.
- git: the host's `gh auth git-credential` helper isn't in the images, so
  HTTPS pushes to GitHub need another way in (e.g. SSH remotes with keys).
- To change the exit node on a running node:
  `docker compose exec tailscale tailscale set --exit-node=<node>`.
- Rootless podman: set `USERNS_MODE=keep-id` so files keep your uid on the
  host. `/dev/net/tun` and `NET_ADMIN` are needed for kernel-mode tailscale.

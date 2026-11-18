# remote-dev

Exposes an existing dev machine's Claude Code, herdr-core and T3 server
state through Tailscale, without running Tailscale on the host. Deploy on the
remote machine and run it only while nobody is working there. The containers
use the same files as the desktop apps, so stop one side before starting the
other.

| service     | what                                   | reach it                                            |
|-------------|----------------------------------------|-----------------------------------------------------|
| `tailscale` | tailnet node with Tailscale SSH; owns the network namespace | —                                     |
| `herdr`     | herdr-core (`hc`) + sshd (loopback only) + Claude Code | `ssh $USER@<TS_HOSTNAME>` / `hc machine add $USER@<TS_HOSTNAME> --name box` (Tailscale SSH, relayed) |
| `t3`        | T3 server (`t3 serve` via `bunx`, headless) | `http://<TS_HOSTNAME>:3773` on the tailnet      |

`herdr` and `t3` use `network_mode: service:tailscale`, so all their
traffic goes through the tailscale container's network stack. If you set
`TS_EXIT_NODE`, all their internet egress also goes through that exit node.
Name resolution still uses the engine's DNS.

## Shared with the host

The images are built for the user who runs compose: same name, uid/gid and
home path. Those come from `$USER`, `$HOME` and `HOST_UID`/`HOST_GID`. Host
dirs are mounted at the same absolute paths:

| host path                    | mounted in       |
|------------------------------|------------------|
| `$WORK_DIR` (`~/dev`)        | herdr, t3        |
| `~/.claude`                  | herdr, t3        |
| `~/.gitconfig`, `~/.config/git` (ro) | herdr, t3        |
| `~/.config/acli` (Atlassian CLI auth) | herdr, t3 |
| `~/.cargo/bin/bb` (Bitbucket CLI, ro, at `/usr/local/bin/bb`) | herdr, t3 |
| `~/.zshrc`, `~/.config/starship.toml` (ro) | herdr |
| `~/.jdks` (ro)               | herdr, t3        |
| `~/.local/state/herdr-core`  | herdr            |
| `~/.m2/repository` (Maven cache) | herdr, t3    |
| `~/.t3`                      | t3               |
| `/var/run/docker.sock`       | herdr, t3        |

All of these must exist on the host. Docker creates a missing source as a
root-owned directory.

### SSH keys

`~/.ssh` is not mounted. To give the containers SSH access to specific hosts,
list them with their keys in `ssh-keys.conf` (see `ssh-keys.conf.example`), one
`<host> <private key>` per line, then run `./ssh-keys.sh`:

```sh
cp ssh-keys.conf.example ssh-keys.conf   # e.g. ssh.bitbucket.org  ~/.ssh/LAPTOP
./ssh-keys.sh                            # re-run after every change
docker compose up -d
```

The script writes `compose.override.yaml` (loaded automatically by docker
compose; gitignored). It bind-mounts into herdr and t3, read-only:

- each listed key and its `.pub`, at the same path as on the host
- `/etc/ssh/ssh_config.d/remote-dev-keys.conf`, with a `Host` block per entry:
  `IdentityFile` + `IdentitiesOnly yes`, plus `HostName`/`Port`/`User` as your
  own ssh config resolves them (`ssh -G`), so aliases work the same
- `/etc/ssh/ssh_known_hosts`, with only those hosts' entries copied from your
  `~/.ssh/known_hosts`. ssh to each host once on the host first; the script
  warns about hosts it has no entry for.

There is no ssh-agent in the containers, so keys with a passphrase prompt for
it (the script warns), and non-interactive git over SSH fails with them.

### Docker

herdr and t3 have the docker CLI (with compose and buildx) and the host's
`/var/run/docker.sock`, so `docker` and `docker compose` inside them drive the
host's engine. There is no daemon in the containers. Set `DOCKER_GID` in `.env`
to the socket's gid (`stat -c %g /var/run/docker.sock`). The image adds the
user to a group with that gid, and you need to rebuild if it changes.

- Bind mounts resolve on the host. Paths under `$WORK_DIR` are the same on both
  sides, so `-v $PWD:/app` and relative mounts in a project's compose file work.
  Paths that exist only inside the container (e.g. `/tmp`) don't.
- Images, containers, volumes and build cache are shared with the host's engine.
- Containers started this way use the host's network, not the tailscale
  network namespace. Their published ports aren't on `localhost` in herdr/t3,
  and their egress doesn't go through `TS_EXIT_NODE`. To share herdr's
  network instead, run them with `--network container:remote-dev-tailscale-1`.
- Access to the socket is root on the host, for anyone who can get a shell in
  herdr or t3 (including through the tailnet `ssh` rule).

## Setup

```sh
cp .env.example .env            # TS_AUTHKEY, HOST_UID/HOST_GID, DOCKER_GID, WORK_DIR if not ~/dev
                                # tailnet policy: an "ssh" rule letting you in as $USER (see below)

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
  latest Bun, Claude Code, herdr-core, acli, worktrunk and Tailscale (the tailscale image is now
  built on top of `tailscale/tailscale:latest`, so it updates on `--build`
  rather than on every `up`). The Claude auto-updater is off, so rebuild to
  update.
- The image is tied to one user. Rebuild if you deploy for a different user or
  uid.
- bb keeps its credentials in the Secret Service, so each container runs its
  own D-Bus session bus and GNOME Keyring (`images/keyring-start.sh`). The
  host's keyring is password-protected, so it can't be shared: run
  `bb auth login` once in herdr and once in t3. The keyring and bb's index
  persist in per-service volumes (`herdr-keyring`/`herdr-bb`,
  `t3-keyring`/`t3-bb`). The container keyrings are unlocked with a fixed
  password, so the secrets are effectively unencrypted at rest in those volumes.
- herdr-core has no TCP API, only a Unix socket. Remote clients reach it over
  SSH, and Tailscale SSH (`--ssh`) handles port 22 on the tailnet IP. Auth is
  your tailnet identity plus the policy's `ssh` rules, not SSH keys. The
  policy needs a rule like
  `{"action": "accept", "src": ["autogroup:member"], "dst": ["autogroup:self"], "users": ["<your $USER>"]}`
  (adjust `dst` if the node is tagged). Running terminals don't move between
  host and container. Each side's core starts its own.
- Tailscale SSH starts sessions in the tailscale container, not in herdr. There,
  `$USER`'s login shell is a relay (`images/herdr-relay.sh`) that runs
  `ssh 127.0.0.1` to herdr's sshd. sshd listens on loopback only, in the shared
  network namespace. It accepts only an internal relay key, which the tailscale
  container generates into the `relay-key` volume and publishes through the
  `relay-authorized-keys` volume. The key is limited to `from="127.0.0.1"`,
  with forwarding disabled. The relay pins herdr's host keys from the
  `ssh-host-keys` volume.
- Only shells and commands are relayed: `ssh`, `ssh host cmd`, `hc machine add`
  / `hc --on`, `scp -O`. sftp (so plain `scp`), port forwarding and agent
  forwarding would run in the tailscale container, not herdr, so don't use
  them.
- Existing nodes: `TS_EXTRA_ARGS` (now incl. `--ssh`) may only be applied on
  first login (`TS_AUTH_ONCE`). If SSH isn't on after upgrading, run
  `docker compose exec tailscale tailscale set --ssh`.
- git: the host's `gh auth git-credential` helper isn't in the images, so
  HTTPS pushes to GitHub need another way in (e.g. SSH remotes with keys, see
  [SSH keys](#ssh-keys)).
- To change the exit node on a running node:
  `docker compose exec tailscale tailscale set --exit-node=<node>`.
- Rootless podman: set `USERNS_MODE=keep-id` so files keep your uid on the
  host. `/dev/net/tun` and `NET_ADMIN` are needed for kernel-mode tailscale.

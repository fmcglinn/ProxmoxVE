# tools/safe — run community-scripts from pinned local checkouts

Upstream runs as `bash -c "$(curl …/main/ct/<app>.sh)"`. Every run then pulls the
engine (`community-scripts/core`) and the install script from GitHub `main`,
on the host and again inside the container. Whatever is on `main` at that moment
runs as root.

This branch leaves every upstream file untouched. It adds:

| File | Purpose |
| --- | --- |
| `cs-run` | Runs `ct/<app>.sh` with all four `COMMUNITY_SCRIPTS_*` roots on local disk (`file://`), telemetry off |
| `cs-sync` | `apply`: builds `../core` at the pinned commit plus the patch. `update`: shows upstream changes, then re-pins |
| `pins.env` | The reviewed `community-scripts/core` commit |
| `core-engine-copy.patch` | One hunk in `pve/backend.func`: copies the engine into the container so nothing is fetched there |
| `check-remote-exec` | Lists lines that hard-code a GitHub fetch and so bypass the local roots |

## Install on the PVE host

```bash
mkdir -p /opt/community-scripts && cd /opt/community-scripts
git clone -b safe-tooling https://github.com/fmcglinn/ProxmoxVE.git
ProxmoxVE/tools/safe/cs-sync apply            # clones core next to it, pins, patches
ln -s /opt/community-scripts/ProxmoxVE/tools/safe/cs-run /usr/local/sbin/cs-run
cs-run debian
```

## Update

On a workstation:

```bash
tools/safe/cs-sync update      # prints both diffs to review, asks, rebases, re-pins
git push --force-with-lease origin safe-tooling
```

On the host: `git -C /opt/community-scripts/ProxmoxVE pull --rebase && …/cs-sync apply`.

`safe-tooling` is rebased onto upstream on every update, so its history is rewritten.

## What it guarantees, and what it does not

- **Guaranteed by the code:** `cs-run` refuses to start if either checkout has local changes, if core is not the pinned commit plus the patch, or if `ct/<app>.sh` or `install/<app>-install.sh` hard-codes a community-scripts GitHub URL. Engine and script lookups then read local disk, and a missing file fails rather than falling back to GitHub.
- **Refused apps** (hard-coded fetches, at time of writing): komodo, alpine-komodo, coolify, dockge, dokploy, runtipi, jellyseerr, overseerr, mysql, homeassistant. Run `check-remote-exec` for the current list.
- **Not covered:** apps still download third-party software at install time (GitHub release tarballs, vendor installers, apt). Those are pinned by neither upstream nor this branch.
- **Not checked:** an install script whose name differs from `<app>-install.sh`. `tools/addon/*` reached some other way.
- **In the container:** the engine is left at the host's core path, and `/usr/bin/update` points at a `file://` path that does not exist there. In-container `update` therefore fails closed. Updating an app is not supported yet (open item).

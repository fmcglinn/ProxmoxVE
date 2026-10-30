# ProxmoxVE, run from pinned local checkouts

A fork of [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)
that runs the same 600+ app scripts without fetching code from GitHub at run time.

Upstream's usage is `bash -c "$(curl …/main/ct/<app>.sh)"`. Each run then
downloads the engine ([community-scripts/core](https://github.com/community-scripts/core))
and the app's install script from GitHub `main`, first on the host and again
inside the new container. Whatever is on `main` at that moment runs as root.
Nothing is reviewed or pinned.

Here, both repos are checked out on the host at commits you have reviewed, and
every script runs from disk. Upstream files are unchanged. Everything this
fork adds lives in [`tools/safe/`](../tools/safe/) and in this file.

> **Status:** the safety checks and host-side loading are tested on Debian 13.
> Creating a container on a real Proxmox VE host is not tested yet.

## Install on the Proxmox VE host

Run as root on the PVE host:

```bash
mkdir -p /opt/community-scripts && cd /opt/community-scripts
git clone https://github.com/fmcglinn/ProxmoxVE.git
ProxmoxVE/tools/safe/cs-sync apply
ln -s /opt/community-scripts/ProxmoxVE/tools/safe/cs-run /usr/local/sbin/cs-run
```

`cs-sync apply` clones `community-scripts/core` into `/opt/community-scripts/core`,
checks out the pinned commit and applies the one local patch.

## Create an app

```bash
cs-run debian
```

The argument is the script name without `.sh`. List them with `ls /opt/community-scripts/ProxmoxVE/ct/`.
The wizard is upstream's, unchanged.

Before it starts, `cs-run` checks that:

1. Neither checkout has local changes.
2. Core is the pinned commit plus the local patch, and nothing else.
3. The app's scripts contain no hard-coded GitHub download (see [Refused apps](#refused-apps)).

Then it points every script and engine path at local disk and turns telemetry off.

## Update to newer upstream

Review and pin on a workstation, then roll out to the host.

On the workstation, in your clone of this fork:

```bash
tools/safe/cs-sync update
```

It prints how many commits each repo moved and the commands to review them:

```bash
git -C ../core diff <old> <new>                                          # engine: runs as root everywhere
git diff <old> <new> -- ct/<app>.sh install/<app>-install.sh              # each app you deploy
```

Read those, then answer `y`. It rebases this branch onto upstream `main`, pins
core to its new commit, re-applies the patch and lists the refused apps. Pin
a specific core commit instead of core's `main` with `cs-sync update <sha>`.

Publish:

```bash
git push --force-with-lease origin safe-tooling
```

The force push is expected: every update rebases this branch.

On the host:

```bash
cd /opt/community-scripts
git -C ProxmoxVE pull --rebase
ProxmoxVE/tools/safe/cs-sync apply
```

## Refused apps

A few upstream scripts write the full GitHub URL instead of going through the
engine's path settings, so they would still download from `main`. `cs-run`
refuses these apps by name. At the last update the list was:

komodo, alpine-komodo, coolify, dockge, dokploy, runtipi, jellyseerr,
overseerr, mysql, homeassistant

To see the current list and the offending lines:

```bash
tools/safe/check-remote-exec
```

## What is protected, and what is not

| | |
| --- | --- |
| Engine and app scripts, on the host | Read from the pinned checkouts. A missing file fails; it never falls back to GitHub. |
| Engine inside the container | Copied in from the host before the install starts (the local patch). |
| Telemetry | Off (`DIAGNOSTICS=no`). |
| Software the app installs | **Not covered.** Release tarballs, vendor installers and apt packages are downloaded at install time, as upstream does. |
| Install scripts not named `<app>-install.sh`, and addons reached indirectly | Not checked by the refusal list. |
| `update` inside a container | Does not work, and fails without fetching anything. Updating apps is an open item. |

## Errors

| Message from `cs-run` | Fix |
| --- | --- |
| `… has local changes` | Commit, stash or discard them. `cs-run` only runs reviewed code. |
| `no core checkout at …` | `tools/safe/cs-sync apply` |
| `core is not pinned … + patch` / `core HEAD is not core-engine-copy.patch` | `tools/safe/cs-sync apply` |
| `refusing <app>` | The app hard-codes a GitHub download; see [Refused apps](#refused-apps). |

| Message from `cs-sync` | Fix |
| --- | --- |
| `core-engine-copy.patch does not apply to <sha>` | Upstream changed `pve/backend.func`. Re-create the patch against that commit. |

## Files

| File | Purpose |
| --- | --- |
| `tools/safe/cs-run` | Runs one app from local disk after the checks above |
| `tools/safe/cs-sync` | `apply`: builds the pinned core. `update`: review, rebase, re-pin |
| `tools/safe/pins.env` | The reviewed core commit |
| `tools/safe/core-engine-copy.patch` | Copies the engine into the container before the install runs |
| `tools/safe/check-remote-exec` | Lists hard-coded GitHub downloads |

The previous attempt at this fork (Dec 2025) is kept as the tag `archive/offline-2025-12`.

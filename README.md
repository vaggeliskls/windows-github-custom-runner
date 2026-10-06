# 🏃 Windows Github Custom Runner

Self-hosted GitHub Actions runners on a Windows Server 2022 VM that you manage like any other Docker container on a Linux host. The container is [dockur/windows](https://github.com/dockur/windows): it installs Windows from the Microsoft evaluation ISO on first start, then this repo's `oem/` scripts install the build toolchain and register the runners. Later starts just boot the installed VM. No custom image, no Vagrant, no libvirt, no privileged container.

⭐ **Don't forget to star the project if it helped you!**

> **Version 2 replaces the Vagrant/libvirt image.** Releases up to 1.3.0 shipped a container image that ran the VM through Vagrant and libvirt and re-provisioned it on every start. That approach is deprecated and no longer maintained. See [Migrating from 1.x](#-migrating-from-1x).

# 📋 Prerequisites

- **Linux host** with hardware virtualization enabled: `/dev/kvm` and `/dev/net/tun` present. Check with `lscpu | grep -i Virtualization` (`VT-x` or `AMD-V`).
- [Docker](https://www.docker.com/) 20 or higher with Compose v2 (`docker compose`).
- Disk: `DISK_SIZE` (default 100 GB) plus about 10 GB for the install ISO under `storage/`.

# 🚥 Authentication for Self-Hosted Runners

Two authentication methods are supported. Set **one** of them in `.env`:

1. Personal Access Token (`PAT`) — a long-lived token you create on GitHub. It needs the *Self-hosted runners: Read and write* permission for organization runners (or admin access to the repository for repository runners). The runner only uses it to fetch a registration token.
2. Registration Token (`TOKEN`) — the short-lived token GitHub shows under *Settings → Actions → Runners → New self-hosted runner*. It expires after one hour, so it must be fresh when the first start reaches the runner step (40 minutes or more in). Prefer `PAT`.

# 🚀 Deployment Guide

1. Clone the repository and create `.env` from the template:

    ```bash
    git clone https://github.com/vaggeliskls/windows-github-custom-runner.git
    cd windows-github-custom-runner
    cp .env.example .env
    ```

    | Variable | Default | Description |
    |---|---|---|
    | `RUNNER_URL` | required | Org (`https://github.com/<org>`) or repo (`https://github.com/<org>/<repo>`) the runners register with |
    | `PAT` / `TOKEN` | one required | See [Authentication](#-authentication-for-self-hosted-runners) |
    | `RUNNERS` | `1` | Number of runners started in the VM |
    | `GITHUB_RUNNER_VERSION` | latest | [actions/runner](https://github.com/actions/runner/releases) release, without the `v` |
    | `GITHUB_RUNNER_NAME` | `windows_x64_dockur` | Runner name prefix |
    | `GITHUB_RUNNER_LABELS` | `windows,win_x64,windows_x64,windows_dockur_action` | Comma-separated labels |
    | `GITHUB_RUNNER_GROUP` | | Runner group (organization runners only) |
    | `RUNNER_HOST_ID` | Windows computer name | Middle part of the runner name, see [Runner names](#-runner-names-and-modes) |
    | `RUNNER_MODE` | `service` | `service` or `interactive`, see [Runner names](#-runner-names-and-modes) |
    | `RUNNER_SERVICE_ACCOUNT` | the Windows user | Service logon account. Built-in accounts such as `NT AUTHORITY\NETWORK SERVICE` need no password |
    | `INSTALL_VISUAL_STUDIO` | `true` | Install Visual Studio 2022 |
    | `VS_EDITION` | `enterprise` | `enterprise`, `professional`, `community` or `buildtools` |
    | `VS_WORKLOADS` | `Microsoft.VisualStudio.Workload.NativeDesktop` | Comma-separated workload ids; `buildtools` wants `Microsoft.VisualStudio.Workload.VCTools` |
    | `INSTALL_RTOOLS` | `true` | Install Rtools 4.0 with `mingw-w64-x86_64-make` |
    | `VERSION` | `2022` | dockur Windows release (`2022` = Windows Server 2022 evaluation) |
    | `RAM_SIZE` / `CPU_CORES` / `DISK_SIZE` | `8G` / `4` / `100G` | VM size |
    | `WIN_USERNAME` / `WIN_PASSWORD` | `Docker` / `admin` | Local administrator created by the install, also the RDP login |

2. Start it and follow the container side (ISO download, QEMU boot):

    ```bash
    docker compose up -d
    docker compose logs -f
    ```

3. Open `http://<host>:8006` to watch the Windows installation. When the desktop appears, a visible `Install` window runs `C:\OEM\install.bat`. Its log is mirrored to the host:

    ```bash
    tail -f shared/install.log
    ```

    `shared/install.done` or `shared/install.failed` appears when it finishes.

> **First start takes 40 to 70 minutes**: ISO download (about 5 GB), Windows setup, Visual Studio, Rtools, runner registration. The runners register at the very end. Later starts take a minute or two and need no provisioning.

The [docker-compose.yml](docker-compose.yml) is self-contained. If you do not want to clone the repo, copy it together with `oem/` and `.env.example`.

## How configuration reaches the VM

`.env` is used twice. Compose reads it for the `${...}` values in [docker-compose.yml](docker-compose.yml) (VM size, Windows user). It is also bind-mounted to `/shared/runner.env`, which dockur exports to the VM as `\\host.lan\Data\runner.env` (drive `Z:`). [install.ps1](oem/install.ps1) reads `RUNNER_URL`, `PAT`, `RUNNERS` and the rest from there.

> **Remove the mount after the first install.** The shared folder is readable by every process in the VM, including the CI jobs your runners execute, so a workflow could read the `PAT` and the Windows password from `Z:\runner.env`. Once `shared/install.done` appears, comment out the `./.env:/shared/runner.env` line in [docker-compose.yml](docker-compose.yml) and run `docker compose up -d`. Put it back only when you re-run `install.ps1`. A one-hour `TOKEN` limits the exposure further.

The `oem/` folder itself holds no secrets on purpose: dockur bakes it into the install ISO that stays in `storage/`, and a PAT should not be kept there. `.env`, `storage/` and `shared/` are git-ignored.

# 🏷 Runner names and modes

Runners register as `<GITHUB_RUNNER_NAME>_<RUNNER_HOST_ID>_<n>`, e.g. `windows_x64_dockur_WIN-ABC123_1`. dockur gives the VM a random computer name at install time, so set `RUNNER_HOST_ID` if you run several VMs against the same org or want names that survive a wipe of `storage/`. Registration uses `--replace`, so re-running takes over an existing registration instead of leaving offline duplicates in GitHub.

- **service** (default): each runner is a Windows service that runs as the Windows user and starts with the VM. No desktop session, which is fine for command-line builds.
- **interactive**: each runner is a scheduled task in the auto-logon desktop session, restarted at every logon. Use it for jobs that drive GUI tooling. This matches what the 1.x image did.

# 🧰 What's in the VM

On top of Windows Server 2022, [install.ps1](oem/install.ps1) installs:

- PowerShell 7, Chocolatey, 7-Zip, Git, jq
- Visual Studio 2022 Enterprise with the *Desktop development with C++* workload (`--includeRecommended`), configurable through `VS_EDITION` and `VS_WORKLOADS`
- Rtools 4.0 with `mingw-w64-x86_64-make`
- Long paths enabled system-wide and in Git; `C:` grown to the full virtual disk

> **Licensing:** Visual Studio Enterprise requires a matching subscription for everyone whose builds use this runner. Set `VS_EDITION=buildtools` and `VS_WORKLOADS=Microsoft.VisualStudio.Workload.VCTools` for a C++ toolchain without that requirement. Windows itself is the 180-day evaluation that dockur installs.

# 🔧 Changing settings later

Edit `.env` on the host, then connect by RDP and run in an elevated PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OEM\install.ps1 -RunnersOnly
```

That removes the old registrations and re-registers with the new count, labels, version or mode. Without `-RunnersOnly` the toolchain steps run again too. To start over completely: `docker compose down`, delete `storage/`, `docker compose up -d`.

`RAM_SIZE`, `CPU_CORES` and `DISK_SIZE` apply on the next `docker compose up`. A larger disk grows `C:` the next time `install.ps1` runs.

# 🌐 Access

| | |
|---|---|
| Web console | `http://<host>:8006` |
| RDP | `<host>:3389` — Linux: [`rdesktop`](https://github.com/rdesktop/rdesktop) or [Remmina](https://remmina.org/); macOS: [Windows App](https://apps.apple.com/us/app/windows-app/id1295203466?mt=12); Windows: Remote Desktop Connection |
| Shared folder | `./shared` on the host is `Z:` in the VM |

# 🔑 User Login

The unattended install creates one local administrator, `WIN_USERNAME` / `WIN_PASSWORD` from `.env` (default `Docker` / `admin`). Change the password before exposing RDP beyond your network.

# 🔁 Migrating from 1.x

| | 1.x (Vagrant + libvirt image) | 2.x (dockur/windows) |
|---|---|---|
| Deployment | `image: vaggeliskls/windows-github-custom-runner` | `dockurr/windows` plus this repo's `oem/` folder, see [docker-compose.yml](docker-compose.yml) |
| Host flags | `privileged: true`, `cgroup: host` | `devices: /dev/kvm, /dev/net/tun`, `cap_add: NET_ADMIN` |
| VM sizing | `MEMORY=8000`, `CPU=4`, `DISK_SIZE=100` | `RAM_SIZE=8G`, `CPU_CORES=4`, `DISK_SIZE=100G` |
| Provisioning | every container start, 20 to 40 min | once, persisted in `storage/` |
| Runner process | `run.cmd` in an interactive session | Windows service (`RUNNER_MODE=interactive` restores the old behaviour) |
| Runner name | `<prefix>_<container hostname>_<n>` | `<prefix>_<RUNNER_HOST_ID>_<n>` |
| Default labels | `...,windows_vagrant_action` | `...,windows_dockur_action`. Workflows that use `runs-on: windows_vagrant_action` should switch to `windows_x64`, or add the old label to `GITHUB_RUNNER_LABELS` |
| Windows login | `vagrant` / `vagrant` | `Docker` / `admin` |
| SSH on 2222 | yes | no; use RDP or the web console |

Remove the old runners from GitHub (*Settings → Actions → Runners*) after the new ones are online; their names differ, so `--replace` does not take them over.

# 🛠 Development

- Everything lives in [oem/install.bat](oem/install.bat), [oem/install.ps1](oem/install.ps1) and [docker-compose.yml](docker-compose.yml). There is no image to build.
- To test script changes, edit `oem/`, delete `storage/` and run `docker compose up -d` again. For runner-only changes, re-run `install.ps1 -RunnersOnly` inside the VM.
- Pull requests run [lint.yml](.github/workflows/lint.yml): `docker compose config`, a PowerShell parse plus [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) on `install.ps1`, and actionlint on the workflows.
- Dependabot keeps the GitHub Actions and the `dockurr/windows` tag current.

# 📚 Further Reading and Resources

- [dockur/windows](https://github.com/dockur/windows) — Windows in a Docker container
- [GitHub: self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [actions/runner releases](https://github.com/actions/runner/releases)
- [Visual Studio workload and component IDs](https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-enterprise)

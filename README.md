# 🏃 Windows Github Custom Runner

Explore an innovative, efficient, and cost-effective approach to deploying a custom GitHub Runner that runs in a containerized Windows OS (x64) environment on a Linux system. This project leverages the robust capabilities of Vagrant VM, libvirt, and Docker Compose, which allows for seamless management of a Windows instance just like any Docker container. The added value here lies in the creation of a plug-and-play solution, significantly enhancing convenience, optimizing resource allocation, and integrating flawlessly with existing workflows. This strategy enriches CI/CD pipeline experiences in various dev-ops environments, providing a smooth and comprehensive approach that does not require prior knowledge of VM creation.

⭐ **Don't forget to star the project if it helped you!**

# 📋 Prerequisites

- **Linux host** with hardware virtualization enabled and `/dev/kvm` present.
  Check with `lscpu | grep -i Virtualization` (`VT-x` or `AMD-V`). Without KVM the VM falls back to plain QEMU and is several times slower.
- [Docker](https://www.docker.com/) 20 or higher with Compose v2 (`docker compose`).
- `privileged: true` and `cgroup: host` in the compose file — libvirt needs both.

# 🚥 Authentication for Self-Hosted Runners

Two authentication methods are supported. Set **one** of them in `.env`:

1. Personal Access Token (`PAT`) — a long-lived token you create on GitHub. It needs the *Self-hosted runners: Read and write* permission for organization runners (or admin access to the repository for repository runners). The runner only uses it to fetch a registration token; it is not stored in the VM.
2. Registration Token (`TOKEN`) — the short-lived token GitHub shows under *Settings → Actions → Runners → New self-hosted runner*. It expires after one hour, so it must be fresh when the container starts.

# 🚀 Deployment Guide

1. Create `.env` from the template and fill it in:

    ```bash
    cp .env.example .env
    ```

    | Variable | Required | Description |
    |---|---|---|
    | `RUNNER_URL` | yes | Org (`https://github.com/<org>`) or repo (`https://github.com/<org>/<repo>`) the runners register with |
    | `PAT` / `TOKEN` | one of | See [Authentication](#-authentication-for-self-hosted-runners) |
    | `RUNNERS` | no (`1`) | Number of runners started in the VM |
    | `MEMORY` | no (`8000`) | VM memory in MiB |
    | `CPU` | no (`4`) | VM vCPUs |
    | `DISK_SIZE` | no (`100`) | VM disk in GiB |
    | `GITHUB_RUNNER_VERSION` | no | Override the [actions/runner](https://github.com/actions/runner/releases) version baked into the image — no rebuild needed |
    | `GITHUB_RUNNER_NAME` | no | Runner name prefix (default `windows_x64_vagrant`) |
    | `GITHUB_RUNNER_LABELS` | no | Comma-separated labels (default `windows,win_x64,windows_x64,windows_vagrant_action`) |

2. Create `docker-compose.yml`:

    ```yaml
    services:
      windows-github-runner-vm:
        image: docker.io/vaggeliskls/windows-github-custom-runner:latest
        platform: linux/amd64
        hostname: windows-github-runner
        env_file: .env
        stdin_open: true
        tty: true
        privileged: true
        cgroup: host
        restart: unless-stopped
        ports:
          - 3389:3389 # RDP
          - 2222:2222 # SSH
    ```

3. Run `docker compose up -d` and follow progress with `docker compose logs -f`.

> **First boot takes a long time.** The Windows box is baked into the image, but the VM still has to boot and run the full provisioning (Chocolatey, Visual Studio, Rtools, runner download). Expect 20–40 minutes depending on hardware and bandwidth; the runners register at the very end, once the toolchain is installed.

## Runner names

Runners are registered as `<GITHUB_RUNNER_NAME>_<container hostname>_<n>`, e.g. `windows_x64_vagrant_windows-github-runner_1`. The names are deliberately stable: when the container restarts, `config.cmd --replace` takes over the existing registrations instead of leaving offline duplicates behind in GitHub.

If you run more than one container against the same org or repo, give each one a different `hostname:` in its compose file.

# 🧰 What's in the VM

Provisioning installs, on top of the base [Windows Server 2022 box](https://github.com/vaggeliskls/windows-in-docker-container):

- PowerShell 7, Chocolatey, 7-Zip, Git, jq
- Visual Studio 2022 Enterprise with the *Desktop development with C++* workload (`--includeRecommended`)
- Rtools 4.0 with `mingw-w64-x86_64-make`
- Long paths enabled, firewall disabled, `C:` grown to the full virtual disk

> **Licensing:** Visual Studio Enterprise requires a matching subscription for everyone whose builds use this runner. If that does not fit, fork the repo and switch [Vagrantfile](Vagrantfile) to `vs_buildtools.exe` with the `Microsoft.VisualStudio.Workload.VCTools` workload.

# 🌐 Access

For debugging or testing you can connect to the VM directly.

### Remote Desktop (RDP) — port `3389`

| OS | Software |
|---|---|
| **Linux** | [`rdesktop`](https://github.com/rdesktop/rdesktop) → `rdesktop <host>:3389`, or [Remmina](https://remmina.org/) |
| **macOS** | [Windows App](https://apps.apple.com/us/app/windows-app/id1295203466?mt=12) (formerly Microsoft Remote Desktop) |
| **Windows** | Built-in **Remote Desktop Connection** |

### SSH — port `2222`

```bash
ssh vagrant@<host> -p 2222
```

# 🔑 User Login

The default users from the Vagrant box are:

1. Administrator
    - Username: `Administrator`
    - Password: `vagrant`
2. User
    - Username: `vagrant`
    - Password: `vagrant`

# 🛠 Development

- The image only adds a [Vagrantfile](Vagrantfile) on top of [windows-in-docker-container](https://github.com/vaggeliskls/windows-in-docker-container); the container startup script comes from the base image.
- `docker compose build` builds the image locally (the base image is large — it contains the Windows box).
- Pull requests run [lint.yml](.github/workflows/lint.yml): `hadolint` on the Dockerfile, `ruby -c` on the Vagrantfile, `actionlint` on the workflows. Publishing a GitHub release builds and pushes the image to Docker Hub and GHCR via [ci.yml](.github/workflows/ci.yml).
- Dependabot keeps the GitHub Actions and the base image tag current. The runner version is set by `GITHUB_RUNNER_VERSION` in the [Dockerfile](Dockerfile).

# 📚 Further Reading and Resources

- [Windows in docker container](https://github.com/vaggeliskls/windows-in-docker-container) (base image)
- [GitHub: self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Windows Vagrant Tutorial](https://github.com/SecurityWeekly/vulhub-lab)
- [Vagrant box: peru/windows-server-2022-standard-x64-eval](https://portal.cloud.hashicorp.com/vagrant/discover/peru/windows-server-2022-standard-x64-eval)
- [Vagrant by HashiCorp](https://www.vagrantup.com/)
- [Windows Virtual Machine in a Linux Docker Container](https://medium.com/axon-technologies/installing-a-windows-virtual-machine-in-a-linux-docker-container-c78e4c3f9ba1)

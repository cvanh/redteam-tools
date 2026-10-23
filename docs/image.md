# Image

The container image is built from the repository's `Dockerfile` (Kali rolling
plus `kali-linux-headless`) by GitHub Actions and published to
`ghcr.io/cvanh/redteam-tools`.

`Dockerfile` installs the default Kali headless metapackages:

```dockerfile
apt-get update && apt-get -y install kali-linux-headless
```

`.github/workflows/image.yaml` builds and pushes it on changes to the
`Dockerfile`, on manual dispatch, and weekly (Kali rolling moves). Published
tags:

| Tag | Purpose |
|---|---|
| `latest` | What `request_container.sh` uses. |
| `kali-YYYYMMDD` | Build date, for pinning. |
| `sha-<commit>` | Exact build, for rollback. |

The workflow authenticates to GHCR with the repository's built-in
`GITHUB_TOKEN` (`packages: write`); no repository secrets are needed. The
`redteam-tools` package must be **public** (Package settings → Change
visibility) because cluster pods pull it anonymously. Pods use
`imagePullPolicy: Always` so a fresh push reaches a node that already cached an
older `latest`.

Build and test locally:

```bash
docker build -t ghcr.io/cvanh/redteam-tools:local .
docker run --rm ghcr.io/cvanh/redteam-tools:local bash -lc 'nmap --version; msfconsole --version'
```

The image is amd64-only; rebuild it after Kubernetes nodes change architecture.
It is about 9 GB uncompressed, so the first Job scheduled on a node can spend
several minutes pulling it; `request_container.sh` waits up to 10 minutes for
readiness. Use a longer `--ttl` for the first run on a fresh node.

Kali's `nmap` binary ships with `cap_net_admin`, which baseline Pod Security
cannot grant; the `Dockerfile` narrows the file capabilities to
`cap_net_raw,cap_net_bind_service` so `nmap` is executable in the Job.

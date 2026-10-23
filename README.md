# bakkie

Short-lived Kali Linux containers on the `compute` Kubernetes cluster.

The container image is built from this repo's `Dockerfile` (Kali rolling plus
`kali-linux-headless`) by GitHub Actions and published to
`ghcr.io/cvanh/redteam-tools`. See [Image](#image).

## Usage

```bash
./bin/request_container.sh                          # 15m interactive Kali shell
./bin/request_container.sh --ttl 45m                # longer session
./bin/request_container.sh --cmd 'nmap -sV 10.0.0.0/24' --rm
./bin/request_container.sh --no-attach --ttl 2h     # create only, print connect command
./bin/request_container.sh --tor --cmd 'curl -fsS https://check.torproject.org/api/ip'
./bin/request_container.sh --dry-run                # print manifests, touch nothing
```

## Options

| Option | Description |
|---|---|
| `--ttl DUR` | Lifetime: `90s`, `15m`, `2h`. Default `15m`, max `2h`. |
| `--name NAME` | Job name. Default: `kali-<timestamp>-<hex>`. |
| `--image IMAGE` | Default `ghcr.io/cvanh/redteam-tools:latest`. |
| `--cmd COMMAND` | Run one command instead of opening a shell. |
| `--no-attach` | Create only; print connect/delete commands. |
| `--rm` | Delete the Job when the shell/command exits. |
| `--tor` | Label the pod `bakkie.io/tor-egress=true` and set `ALL_PROXY`/`HTTP(S)_PROXY` to the in-cluster Tor SOCKS5 proxy. See [Tor egress](#tor-egress). |
| `--dry-run` | Print bootstrap and Job manifests without cluster calls. |
| `--host USER@HOST` | Override the SSH destination. |

## Image

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

## Tor egress

`deploy/tor-egress/` runs a Tor SOCKS5 proxy in namespace `tor-egress` and a
NetworkPolicy in `kali`. Pods labelled `bakkie.io/tor-egress=true`:

- may open TCP connections only to
  `tor-proxy.tor-egress.svc.cluster.local:9050`;
- may query cluster DNS, so local `getaddrinfo()` calls work;
- may not accept inbound connections;
- have every other egress packet dropped, including UDP and ICMP.

The policy is fail-closed: labelling a pod without pointing its clients at the
proxy makes egress fail instead of leaking over the node's route. `--tor` does
both, and uses `socks5h://` so names are resolved by Tor rather than the
cluster resolver.

NetworkPolicy is namespace-scoped, so this policy only covers `kali`. If
another sandbox namespace is added, copy `networkpolicy-kali.yaml` into it and
change `metadata.namespace`.

Applications that honour `ALL_PROXY`/`HTTP(S)_PROXY` (curl, git, most Go and
Rust HTTP clients) need no further setup. For raw-socket tools, use the
`proxychains4` shipped in the image:

```bash
printf '[ProxyList]\nsocks5 tor-proxy.tor-egress.svc.cluster.local 9050\n' \
  > /tmp/tor-proxychains.conf
PROXYCHAINS_CONF_FILE=/tmp/tor-proxychains.conf proxychains4 -q nmap -sT -Pn example.com
```

Tor forwards TCP only, so UDP-based scans and ICMP do not work through it.

### Deployment

`.github/workflows/tor-egress.yaml` applies the configuration through Argo CD
whenever `deploy/` changes. It installs or upgrades the pinned Argo CD release,
then applies the `bakkie` AppProject and the `bakkie-tor-egress` Application,
which reconciles `deploy/tor-egress` from `master` with automated prune and
self-heal.

The workflow requires two repository secrets:

| Secret | Value |
|---|---|
| `CLUSTER_SSH_KEY` | Private key allowed to log in as `ubuntu@45.135.58.222`. |
| `CLUSTER_KNOWN_HOSTS` | Output of `ssh-keyscan 45.135.58.222`. |

Argo CD runs in namespace `argocd`; the repository is public, so no
repository credentials are stored in the cluster. Check the Application with:

```bash
ssh ubuntu@45.135.58.222 'sudo -n k8s kubectl -n argocd get application bakkie-tor-egress'
```

## Lifecycle

Each request creates a Kubernetes Job in namespace `kali`:

- `activeDeadlineSeconds` enforces the TTL.
- `ttlSecondsAfterFinished: 120` deletes the Job and pod after expiry.
- A ResourceQuota caps usage at 4 Jobs, 2 CPU, and 2Gi memory.
- Pods run unprivileged with baseline Pod Security, no Service, no host mounts, and no service-account token.
- Access is only through `kubectl exec` over SSH; nothing is exposed on the network.

Without `--rm`, the Job remains until its TTL expires. Use the printed delete command to remove it early:

```bash
ssh ubuntu@45.135.58.222 'sudo -n k8s kubectl delete job -n kali <name>'
```

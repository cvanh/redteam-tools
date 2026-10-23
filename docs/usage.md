# Usage

All requests go through `bin/request_container.sh`, which creates a Kubernetes
Job in the `kali` namespace:

```bash
./bin/request_container.sh                          # 15m interactive Kali shell (Tor egress)
./bin/request_container.sh --ttl 45m                # longer session
./bin/request_container.sh --cmd 'nmap -sV 10.0.0.0/24' --rm
./bin/request_container.sh --no-tor --cmd 'nmap -sV 10.0.0.0/24' --rm
./bin/request_container.sh --no-attach --ttl 2h     # create only, print connect command
./bin/request_container.sh --cmd 'curl -fsS https://check.torproject.org/api/ip'
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
| `--tor` | Default. Label the pod `bakkie.io/tor-egress=true` and set `ALL_PROXY`/`HTTP(S)_PROXY` to the in-cluster Tor SOCKS5 proxy. See [Tor egress](tor-egress.md). |
| `--no-tor` | Use the node's normal egress route instead of the Tor proxy. |
| `--dry-run` | Print bootstrap and Job manifests without cluster calls. |
| `--host USER@HOST` | Override the SSH destination. |

Job resources and cleanup are described in [Lifecycle](lifecycle.md).

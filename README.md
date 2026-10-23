# bakkie

Short-lived Kali Linux containers on the `compute` Kubernetes cluster.

## Usage

```bash
./bin/request_container.sh                          # 15m interactive Kali shell
./bin/request_container.sh --ttl 45m                # longer session
./bin/request_container.sh --cmd 'nmap -sV 10.0.0.0/24' --rm
./bin/request_container.sh --no-attach --ttl 2h     # create only, print connect command
./bin/request_container.sh --dry-run                # print manifests, touch nothing
```

Requirements: SSH access to `ubuntu@45.135.58.222`; no local `kubectl` or kubeconfig needed.

## Options

| Option | Description |
|---|---|
| `--ttl DUR` | Lifetime: `90s`, `15m`, `2h`. Default `15m`, max `2h`. |
| `--name NAME` | Job name. Default `kali-<timestamp>-<hex>`. |
| `--image IMAGE` | Default `docker.io/kalilinux/kali-rolling:latest`. |
| `--cmd COMMAND` | Run one command instead of opening a shell. |
| `--no-attach` | Create only; print connect/delete commands. |
| `--rm` | Delete the Job when the shell/command exits. |
| `--dry-run` | Print bootstrap and Job manifests without cluster calls. |
| `--host USER@HOST` | Override the SSH destination. |

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

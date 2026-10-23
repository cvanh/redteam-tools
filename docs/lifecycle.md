# Lifecycle

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

# Tor egress

`deploy/tor-egress/` runs a Tor SOCKS5 proxy in namespace `tor-egress` and a
NetworkPolicy in `kali`. Pods labelled `bakkie.io/tor-egress=true`:

- may open TCP connections only to
  `tor-proxy.tor-egress.svc.cluster.local:9050`;
- may query cluster DNS, so local `getaddrinfo()` calls work;
- may not accept inbound connections;
- have every other egress packet dropped, including UDP and ICMP.

The policy is fail-closed: labelling a pod without pointing its clients at the
proxy makes egress fail instead of leaking over the node's route. `--tor` (the
default) does both, and uses `socks5h://` so names are resolved by Tor rather
than the cluster resolver. Pass `--no-tor` to skip the label and proxy
variables and use the node's normal egress route.

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

## Deployment

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

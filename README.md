# bakkie

Short-lived Kali Linux containers on the `compute` Kubernetes cluster.

The container image is built from this repo's `Dockerfile` (Kali rolling plus
`kali-linux-headless`) by GitHub Actions and published to
`ghcr.io/cvanh/redteam-tools`.

## Quick start

```bash
./bin/request_container.sh
```

That opens a 15-minute interactive Kali shell with egress routed through the
cluster Tor SOCKS5 proxy. See [Usage](docs/usage.md) for longer sessions,
one-shot commands, `--no-tor`, and dry runs.

## Documentation

| Document | Contents |
|---|---|
| [Usage](docs/usage.md) | Request commands and all `request_container.sh` options. |
| [Image](docs/image.md) | Build workflow, published tags, local build and test, capabilities. |
| [Tor egress](docs/tor-egress.md) | SOCKS5 proxy, NetworkPolicy behaviour, proxychains, Argo CD deployment. |
| [Lifecycle](docs/lifecycle.md) | Job resources, TTL enforcement, and cleanup. |

#!/usr/bin/env bash
# request_container.sh - create a short-lived Kali Linux sandbox on the compute cluster.
#
# The cluster has no local kubeconfig; all Kubernetes calls go through SSH to the
# control-plane host, which exposes the "k8s" snap wrapper.
set -euo pipefail

readonly DEFAULT_HOST="ubuntu@45.135.58.222"
readonly NAMESPACE="kali"
readonly DEFAULT_IMAGE="ghcr.io/cvanh/redteam-tools:latest"
readonly DEFAULT_TTL="15m"
readonly MAX_TTL_SECONDS=$((2 * 3600))
readonly MIN_TTL_SECONDS=30
readonly CLEANUP_GRACE_SECONDS=120
readonly READY_TIMEOUT_SECONDS=600
readonly SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: bin/request_container.sh [options]

Create an isolated Kali Linux Job in the compute cluster, wait for it, and
optionally attach an interactive shell.

Options:
  --ttl DUR       Lifetime of the Job. Examples: 90s, 15m, 2h.
                  Default: 15m. Maximum: 2h.
  --name NAME     Explicit Job name. Default: kali-<UTC timestamp>-<random hex>.
  --image IMAGE   Container image. Default: ghcr.io/cvanh/redteam-tools:latest.
  --cmd COMMAND   Run COMMAND non-interactively instead of opening a shell.
  --no-attach     Create the Job, print how to connect, and exit.
  --rm            Delete the Job when the shell/command exits.
                  Without --rm the Job lives until --ttl expires.
  --tor           Send egress through the cluster Tor SOCKS5 proxy (default).
                  Labels the pod bakkie.io/tor-egress=true, which makes the
                  tor-egress NetworkPolicy permit only the proxy and DNS.
  --no-tor        Use the node's normal egress route instead of Tor.
  --dry-run       Print the manifests and remote commands without touching the cluster.
  --host USER@HOST
                  SSH destination. Default: ubuntu@45.135.58.222.
  -h, --help      Show this help.

Examples:
  bin/request_container.sh
  bin/request_container.sh --ttl 45m
  bin/request_container.sh --cmd 'curl -fsS https://check.torproject.org/api/ip' --rm
  bin/request_container.sh --no-tor --cmd 'nmap -sV 10.0.0.0/24' --rm
  bin/request_container.sh --no-attach --ttl 2h
EOF
}

parse_ttl() {
  local value=$1 number unit seconds
  if [[ ! $value =~ ^([0-9]{1,5})([smh])$ ]]; then
    printf 'error: invalid TTL %q (use e.g. 90s, 15m, 2h)\n' "$value" >&2
    return 1
  fi
  number=$((10#${BASH_REMATCH[1]}))
  unit=${BASH_REMATCH[2]}
  case $unit in
    s) seconds=$number ;;
    m) seconds=$((number * 60)) ;;
    h) seconds=$((number * 3600)) ;;
  esac
  if ((seconds < MIN_TTL_SECONDS)); then
    printf 'error: TTL must be at least %ss\n' "$MIN_TTL_SECONDS" >&2
    return 1
  fi
  if ((seconds > MAX_TTL_SECONDS)); then
    printf 'error: TTL must be at most %ss (%sh)\n' "$MAX_TTL_SECONDS" "$((MAX_TTL_SECONDS / 3600))" >&2
    return 1
  fi
  printf '%s\n' "$seconds"
}

print_bootstrap() {
  cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: kali
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: baseline
    pod-security.kubernetes.io/warn: baseline
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: kali-quota
  namespace: ${NAMESPACE}
spec:
  hard:
    pods: "4"
    count/jobs.batch: "4"
    requests.cpu: "1"
    requests.memory: 1Gi
    requests.ephemeral-storage: 4Gi
    limits.cpu: "2"
    limits.memory: 2Gi
    limits.ephemeral-storage: 8Gi
EOF
}

print_manifest() {
  local tor_label="" tor_env=""
  if ((tor_egress)); then
    tor_label='        bakkie.io/tor-egress: "true"'
    # socks5h resolves names at the proxy, so applications that honour these
    # variables never leak DNS. The NetworkPolicy still limits non-proxy egress.
    tor_env=$(cat <<'PROXY_ENV'
          env:
            - name: ALL_PROXY
              value: socks5h://tor-proxy.tor-egress.svc.cluster.local:9050
            - name: all_proxy
              value: socks5h://tor-proxy.tor-egress.svc.cluster.local:9050
            - name: HTTPS_PROXY
              value: socks5h://tor-proxy.tor-egress.svc.cluster.local:9050
            - name: https_proxy
              value: socks5h://tor-proxy.tor-egress.svc.cluster.local:9050
            - name: HTTP_PROXY
              value: socks5h://tor-proxy.tor-egress.svc.cluster.local:9050
            - name: http_proxy
              value: socks5h://tor-proxy.tor-egress.svc.cluster.local:9050
PROXY_ENV
)
  fi
  cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${name}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: kali
    app.kubernetes.io/managed-by: request-container
    bakkie.io/ttl-seconds: "${ttl_seconds}"
    bakkie.io/created-at: "$(date -u '+%Y%m%dT%H%M%SZ')"
spec:
  activeDeadlineSeconds: ${ttl_seconds}
  ttlSecondsAfterFinished: ${CLEANUP_GRACE_SECONDS}
  backoffLimit: 0
  template:
    metadata:
      labels:
        app.kubernetes.io/name: kali
        app.kubernetes.io/managed-by: request-container
        job-name: ${name}
${tor_label}
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      enableServiceLinks: false
      terminationGracePeriodSeconds: 5
      securityContext:
        runAsUser: 0
        runAsGroup: 0
        runAsNonRoot: false
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: kali
          image: ${image}
          # :latest is mutable; Always keeps nodes from serving a cached build
          # after a new image is pushed.
          imagePullPolicy: Always
          command: ["sleep", "infinity"]
          # Keep the default capability set (which includes NET_RAW for
          # nmap/tcpdump-style tools); explicitly adding NET_RAW is rejected by
          # the baseline Pod Security Standard.
          securityContext:
            allowPrivilegeEscalation: false
${tor_env}
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
              ephemeral-storage: 1Gi
            limits:
              cpu: "1"
              memory: 1Gi
              ephemeral-storage: 4Gi
EOF
}

remote_kubectl() {
  ssh "${SSH_OPTS[@]}" "$host" "sudo -n k8s kubectl $(printf '%q ' "$@")"
}

remote_apply_stdin() {
  ssh "${SSH_OPTS[@]}" "$host" 'sudo -n k8s kubectl apply -f -'
}

host=$DEFAULT_HOST
image=$DEFAULT_IMAGE
ttl_raw=$DEFAULT_TTL
name=""
cmd=""
no_attach=0
rm_after=0
dry_run=0
tor_egress=1
job_created=0

cleanup_on_interrupt() {
  if ((job_created && rm_after)); then
    printf '\nInterrupted; deleting Job %s...\n' "$name" >&2
    remote_kubectl delete job "$name" -n "$NAMESPACE" --ignore-not-found \
      --cascade=foreground --wait=true >/dev/null 2>&1 || true
  fi
  exit 130
}
trap cleanup_on_interrupt INT TERM

while (($# > 0)); do
  case $1 in
    --ttl)
      [[ $# -ge 2 ]] || die "--ttl requires a value"
      ttl_raw=$2
      shift 2
      ;;
    --ttl=*)
      ttl_raw=${1#*=}
      shift
      ;;
    --name)
      [[ $# -ge 2 ]] || die "--name requires a value"
      name=$2
      shift 2
      ;;
    --name=*)
      name=${1#*=}
      shift
      ;;
    --image)
      [[ $# -ge 2 ]] || die "--image requires a value"
      image=$2
      shift 2
      ;;
    --image=*)
      image=${1#*=}
      shift
      ;;
    --cmd)
      [[ $# -ge 2 ]] || die "--cmd requires a value"
      cmd=$2
      shift 2
      ;;
    --cmd=*)
      cmd=${1#*=}
      shift
      ;;
    --no-attach)
      no_attach=1
      shift
      ;;
    --rm)
      rm_after=1
      shift
      ;;
    --tor)
      tor_egress=1
      shift
      ;;
    --no-tor)
      tor_egress=0
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --host)
      [[ $# -ge 2 ]] || die "--host requires a value"
      host=$2
      shift 2
      ;;
    --host=*)
      host=${1#*=}
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      die "unknown argument: $1 (use --help)"
      ;;
  esac
done

(($# == 0)) || die "unexpected arguments: $*"

[[ $host =~ ^[A-Za-z0-9._@:-]+$ && $host != -* ]] || die "invalid SSH host: $host"
[[ $image =~ ^[A-Za-z0-9._/:@+-]+$ ]] || die "invalid image reference: $image"
ttl_seconds=$(parse_ttl "$ttl_raw") || exit 1

if [[ -n $name ]]; then
  [[ $name =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "invalid Job name: $name"
  ((${#name} <= 63)) || die "Job name must be 63 characters or fewer"
else
  name="kali-$(date -u '+%Y%m%d-%H%M%S')-$(printf '%04x' $((RANDOM % 65536)))"
fi

if (($no_attach)); then
  [[ -z $cmd ]] || die "--cmd and --no-attach are mutually exclusive"
  if ((rm_after)); then
    printf 'warning: --rm is ignored with --no-attach\n' >&2
    rm_after=0
  fi
else
  if [[ -z $cmd ]] && ! { [[ -t 0 ]] && [[ -t 1 ]]; }; then
    no_attach=1
  fi
fi

if ((dry_run)); then
  printf '# --- bootstrap (Namespace + ResourceQuota) ---\n'
  print_bootstrap
  printf '\n# --- Job ---\n'
  print_manifest
  printf '\n# --- expected remote commands (pod name resolved at runtime) ---\n'
  printf 'ssh -t %s "sudo -n k8s kubectl exec -it -n %s <pod> -- bash -l"\n' "$host" "$NAMESPACE"
  printf 'ssh %s "sudo -n k8s kubectl delete job -n %s %s --ignore-not-found"\n' "$host" "$NAMESPACE" "$name"
  exit 0
fi

printf 'Applying %s namespace and quota on %s...\n' "$NAMESPACE" "$host"
if ! print_bootstrap | remote_apply_stdin >/dev/null; then
  die "failed to apply Namespace/ResourceQuota bootstrap"
fi

if ((tor_egress)); then
  if ! remote_kubectl get networkpolicy tor-egress-only -n "$NAMESPACE" >/dev/null 2>&1; then
    die "--tor requires NetworkPolicy ${NAMESPACE}/tor-egress-only; run the tor-egress GitHub workflow first"
  fi
fi

if remote_kubectl get job "$name" -n "$NAMESPACE" >/dev/null 2>&1; then
  die "Job ${NAMESPACE}/${name} already exists"
fi

printf 'Creating job %s...\n' "$name"
if ! print_manifest | remote_apply_stdin >/dev/null; then
  die "failed to create Job ${name}"
fi
job_created=1

pod=""
phase=""
ready=""
deadline=$((SECONDS + READY_TIMEOUT_SECONDS))
while ((SECONDS < deadline)); do
  line=$(remote_kubectl get pod -n "$NAMESPACE" -l "job-name=$name" \
    -o jsonpath='{.items[0].metadata.name}{"|"}{.items[0].status.phase}{"|"}{.items[0].status.containerStatuses[0].ready}' \
    2>/dev/null || true)
  IFS='|' read -r pod phase ready <<<"$line"
  if [[ -n $pod ]]; then
    if [[ $phase == Failed || $phase == Succeeded ]]; then
      remote_kubectl describe pod -n "$NAMESPACE" -l "job-name=$name" >&2 || true
      remote_kubectl logs -n "$NAMESPACE" -l "job-name=$name" --tail=50 >&2 || true
      die "pod for Job ${name} entered phase ${phase}"
    fi
    if [[ $phase == Running && $ready == true ]]; then
      break
    fi
  fi
  sleep 2
done

if [[ -z $pod || $phase != Running || $ready != true ]]; then
  printf 'error: pod did not become ready within %ss\n' "$READY_TIMEOUT_SECONDS" >&2
  remote_kubectl describe job "$name" -n "$NAMESPACE" >&2 || true
  remote_kubectl describe pod -n "$NAMESPACE" -l "job-name=$name" >&2 || true
  remote_kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp 2>/dev/null | tail -20 >&2 || true
  exit 1
fi

expires=$(date -u -d "+${ttl_seconds} seconds" '+%Y-%m-%d %H:%M:%SZ')
printf 'Job:   %s/%s\n' "$NAMESPACE" "$name"
printf 'Pod:   %s\n' "$pod"
printf 'TTL:   %s (expires %s, cleanup up to %ss later)\n' "$ttl_raw" "$expires" "$CLEANUP_GRACE_SECONDS"

if ((no_attach)); then
  printf '\nConnect:\n  ssh -t %s "sudo -n k8s kubectl exec -it -n %s %s -- bash -l"\n' "$host" "$NAMESPACE" "$pod"
  printf 'Delete:\n  ssh %s "sudo -n k8s kubectl delete job -n %s %s --ignore-not-found"\n' "$host" "$NAMESPACE" "$name"
  exit 0
fi

interactive=0
if [[ -t 0 ]] && [[ -t 1 ]]; then
  interactive=1
fi

exec_args=(exec -n "$NAMESPACE" "$pod")
if ((interactive)); then
  exec_args+=(-it)
else
  exec_args+=(-i)
fi
exec_args+=(--)

if [[ -n $cmd ]]; then
  encoded=$(printf '%s' "$cmd" | base64 | tr -d '\n')
  exec_args+=(bash -lc "echo ${encoded} | base64 -d | bash -l")
  printf '\nRunning command in %s...\n' "$pod"
else
  exec_args+=(bash -l)
  printf '\nAttaching to %s (exit shell; Job expires via TTL)...\n' "$pod"
fi

if ((interactive)); then
  ssh_cmd=(ssh -t "${SSH_OPTS[@]}" "$host")
else
  ssh_cmd=(ssh "${SSH_OPTS[@]}" "$host")
fi

if "${ssh_cmd[@]}" "sudo -n k8s kubectl $(printf '%q ' "${exec_args[@]}")"; then
  status=0
else
  status=$?
fi

if ((rm_after)); then
  printf 'Deleting job %s...\n' "$name"
  remote_kubectl delete job "$name" -n "$NAMESPACE" --ignore-not-found \
    --cascade=foreground --wait=true >/dev/null 2>&1 || true
fi

exit "$status"

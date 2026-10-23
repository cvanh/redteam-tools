# Kali rolling with the default headless metapackages preinstalled.
#
# Published by .github/workflows/image.yaml as ghcr.io/cvanh/redteam-tools.
# bin/request_container.sh pulls the :latest tag, so rebuilding this image is
# how tools get added to request containers.
FROM docker.io/kalilinux/kali-rolling:latest

LABEL org.opencontainers.image.title="redteam-tools" \
      org.opencontainers.image.description="Kali rolling with kali-linux-headless for bakkie request containers" \
      org.opencontainers.image.source="https://github.com/cvanh/redteam-tools"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# One layer: refresh indexes, install the default headless selection, prove the
# metapackage and its key tools landed, then drop the apt metadata.
#
# Kali's nmap binary carries cap_net_admin. Baseline Pod Security forbids
# NET_ADMIN, and execve() refuses any file capability outside the container's
# bounding set, so unmodified nmap fails with "Operation not permitted". Keep
# only capabilities in the default Kubernetes set; the Job runs as root, so
# raw sockets still work.
RUN set -eux; \
    apt-get update; \
    apt-get -y install kali-linux-headless; \
    dpkg -s kali-linux-headless > /dev/null; \
    for tool in nmap msfconsole hydra tcpdump; do command -v "$tool" > /dev/null; done; \
    setcap cap_net_bind_service,cap_net_raw+ep /usr/lib/nmap/nmap; \
    nmap --version > /dev/null; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /root
CMD ["bash", "-l"]

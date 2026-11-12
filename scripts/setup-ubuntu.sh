#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then echo "Run as your normal user (sudo is used where needed)."; exit 1; fi

echo "==> Base packages"
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg jq tree zip unzip rsync python3-venv

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Docker Engine (official apt repository)"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
fi

if ! command -v microk8s >/dev/null 2>&1; then
  echo "==> MicroK8s"
  sudo snap install microk8s --classic
  sudo usermod -aG microk8s "$USER"
  mkdir -p ~/.kube && sudo chown -R "$USER" ~/.kube
fi

echo "==> MicroK8s add-ons (dns, helm3)"
sudo microk8s status --wait-ready
sudo microk8s enable dns
sudo microk8s enable helm3 || true

sudo snap alias microk8s.kubectl kubectl 2>/dev/null || true
sudo snap alias microk8s.helm3 helm 2>/dev/null || true
sudo microk8s config > ~/.kube/config && chmod 600 ~/.kube/config

cat <<'MSG'

Done. Log out and back in (or run `newgrp docker` and `newgrp microk8s`) so the group
changes apply, then verify with:   ./scripts/collect-artifact.sh versions
MSG

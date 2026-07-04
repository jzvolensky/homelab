#!/usr/bin/env bash
# Install the CLI tooling this repo needs onto the *deploy machine* (your WSL box).
# These are REMOTE-CONTROL CLIENTS — they run here and talk to the Proxmox host
# and the Talos cluster over the network. Nothing is installed on the node itself
# (Talos is immutable). Everything lands in ~/.local/bin as a plain binary — no
# sudo, no apt repos, so it sidesteps the /etc/apt/sources.list.d hashicorp break.
#
#   terraform  provision the VM + Talos cluster
#   kubectl    client for the remote Kubernetes API
#   talosctl   client for the remote Talos API (day-2: health, upgrades, dashboard)
#
# NOT installed here: helm (no longer used), ansible (managed by uv in infra/ansible),
# kubeseal (only needed later when sealing secrets — see note at the end).
#
# Usage: bash scripts/install-tools.sh
set -euo pipefail

BIN="${HOME}/.local/bin"
mkdir -p "$BIN"

# Pin versions — bump deliberately. Keep TERRAFORM/TALOS in sync with infra/terraform.
TERRAFORM_VERSION="1.10.5"
TALOS_VERSION="v1.13.5" # keep in sync with talos_version in terraform.tfvars

arch="amd64"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo ">> terraform ${TERRAFORM_VERSION}"
curl -fsSL -o "$tmp/tf.zip" \
  "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip"
unzip -o -q "$tmp/tf.zip" -d "$tmp"
install -m 0755 "$tmp/terraform" "$BIN/terraform"

echo ">> talosctl ${TALOS_VERSION}"
curl -fsSL -o "$BIN/talosctl" \
  "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-${arch}"
chmod +x "$BIN/talosctl"

echo ">> kubectl (latest stable)"
kver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSL -o "$BIN/kubectl" "https://dl.k8s.io/release/${kver}/bin/linux/${arch}/kubectl"
chmod +x "$BIN/kubectl"

echo
echo "Installed into ${BIN}:"
for t in terraform talosctl kubectl; do printf "  %-10s %s\n" "$t" "$("$BIN/$t" version 2>/dev/null | head -1 || echo '?')"; done
echo
echo "Later, to seal secrets, grab kubeseal too:"
echo "  https://github.com/bitnami-labs/sealed-secrets/releases (kubeseal-<ver>-linux-amd64.tar.gz)"
echo
case ":$PATH:" in
  *":$BIN:"*) echo "PATH already includes $BIN — you're good." ;;
  *) echo "NOTE: add this to your ~/.bashrc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

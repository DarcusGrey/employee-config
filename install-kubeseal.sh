#!/usr/bin/env bash

# Exit immediately if a command fails, and treat unset variables as an error
set -euo pipefail

echo "========================================"
echo "📦 Installing Kubernetes Local Tools..."
echo "========================================"

# --- 1. Install Kubeseal ---
echo -e "\n⏳ Downloading and installing Kubeseal (v0.38.0)..."
KUBESEAL_VERSION="0.38.0"
TAR_FILE="kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"

curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/${TAR_FILE}"
tar -xvzf "$TAR_FILE" kubeseal

# Install to /usr/local/bin (requires sudo)
echo "🔒 Prompting for sudo to move kubeseal to /usr/local/bin..."
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Cleanup Kubeseal tarball and extracted binary
rm -f "$TAR_FILE" kubeseal
echo "✅ Kubeseal installed successfully."

#!/usr/bin/env bash

# Exit immediately if a command fails, and treat unset variables as an error
set -euo pipefail

# --- Configuration Variables ---
CERT_FILE="sealed-secrets-cert.pem"
TEMP_FILE="secret-temp.yaml"
CHART_DIR="./employee-chart"

# --- Security Cleanup ---
# This ensures the raw plain-text secret file is ALWAYS deleted when the script finishes or crashes.
trap 'rm -f "$TEMP_FILE"' EXIT

echo "🔒 Fetching sealed-secrets public certificate from the cluster..."
kubeseal --fetch-cert --controller-name=sealed-secrets --controller-namespace=kube-system > "$CERT_FILE"

# ---------------------------------------------------------
echo "⚙️  Sealing secrets for: LOCAL..."
helm template employee-app "$CHART_DIR" \
  -f secrets/secret-values.yaml \
  --set sealingSecret=true \
  -n employee \
  --show-only templates/secrets_template.yaml > "$TEMP_FILE"

kubeseal --cert "$CERT_FILE" -f "$TEMP_FILE" -o yaml -n employee > sources/sealed-secrets.yaml

# ---------------------------------------------------------
echo "⚙️  Sealing secrets for: DEV..."
helm template employee-app "$CHART_DIR" \
  -f dev/values-dev.yaml \
  -f secrets/secret-values-dev.yaml \
  -n employee-dev \
  --set sealingSecret=true \
  --show-only templates/secrets_template.yaml > "$TEMP_FILE"

kubeseal --cert "$CERT_FILE" -f "$TEMP_FILE" -o yaml -n employee-dev > dev/sources/sealed-secrets-dev.yaml

# ---------------------------------------------------------
echo "⚙️  Sealing secrets for: PROD..."
helm template employee-app "$CHART_DIR" \
  -f prod/values-prod.yaml \
  -f secrets/secret-values-prod.yaml \
  -n employee-prod \
  --set sealingSecret=true \
  --show-only templates/secrets_template.yaml > "$TEMP_FILE"

# Note: Fixed the output directory from 'dev/sources/...' to 'prod/sources/...'
kubeseal --cert "$CERT_FILE" -f "$TEMP_FILE" -o yaml -n employee-prod > prod/sources/sealed-secrets-prod.yaml

# ---------------------------------------------------------
echo "✅ All secrets successfully sealed!"
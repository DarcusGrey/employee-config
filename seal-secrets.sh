#!/usr/bin/env bash
CLUSTERS=("cluster1" "cluster2")

# Exit immediately if a command fails, and treat unset variables as an error
set -euo pipefail

# --- Configuration Variables ---
TEMP_FILE="secret-temp.yaml"
CHART_DIR="./employee-chart"

# --- Security Cleanup ---
# This ensures the raw plain-text secret file is ALWAYS deleted when the script finishes or crashes.

trap 'rm -f "$TEMP_FILE"' EXIT

for CLUSTER in "${CLUSTERS[@]}"; do
    echo "  -> Processing ${CLUSTER}..."
    CERT_FILE="certificates/${CLUSTER}-sealed-secrets-cert.pem"

    # 1. Fetch the specific certificate for THIS cluster
    echo "     🔒 Fetching certificate from ${CLUSTER}..."
    kubeseal --fetch-cert \
      --controller-name=sealed-secrets \
      --controller-namespace=kube-system \
      --context "$CLUSTER" > "$CERT_FILE"

    echo "⚙️  Sealing secrets for: LOCAL..."
    helm template employee-app "$CHART_DIR" \
      -f secrets/secret-values.yaml \
      --set sealingSecret=true \
      --set cluster.name="$CLUSTER" \
      -n employee \
      --show-only templates/secrets_template.yaml > "$TEMP_FILE"

    kubeseal --cert "$CERT_FILE" -f "$TEMP_FILE" -o yaml -n employee > sources/${CLUSTER}-sealed-secrets.yaml

      # ---------------------------------------------------------
    echo "⚙️  Sealing secrets for: DEV..."
    helm template employee-app "$CHART_DIR" \
      -f dev/values-dev.yaml \
      -f secrets/secret-values-dev.yaml \
      -n employee-dev \
      --set sealingSecret=true \
      --set cluster.name="$CLUSTER" \
      --show-only templates/secrets_template.yaml > "$TEMP_FILE"

    kubeseal --cert "$CERT_FILE" -f "$TEMP_FILE" -o yaml -n employee-dev > dev/sources/${CLUSTER}-sealed-secrets-dev.yaml

  # ---------------------------------------------------------
  echo "⚙️  Sealing secrets for: PROD..."
  helm template employee-app "$CHART_DIR" \
    -f prod/values-prod.yaml \
    -f secrets/secret-values-prod.yaml \
    -n employee-prod \
    --set sealingSecret=true \
    --set cluster.name="$CLUSTER" \
    --show-only templates/secrets_template.yaml > "$TEMP_FILE"

    echo "     ✅ Done with ${CLUSTER}."
done


echo "✅ All secrets successfully sealed!"
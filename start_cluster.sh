#!/bin/bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

CLUSTERS=("cluster1" "cluster2")
POD_CIDR_INDEX=244

# Directory that will be mounted into every Minikube node
ENC_DIR="$(pwd)/enc"

mkdir -p "${ENC_DIR}"

cleanup() {
    rm -f "${ENC_DIR}"/encryption-config-*.yaml
    rm -f "${ENC_DIR}/encryption-config.yaml"
}

trap cleanup EXIT

# -----------------------------------------------------------------------------
# Create clusters
# -----------------------------------------------------------------------------

for CLUSTER_NAME in "${CLUSTERS[@]}"; do

    echo
    echo "========================================================="
    echo "Creating ${CLUSTER_NAME}"
    echo "========================================================="

    # Generate a 32-byte AES key (single-line Base64)
    if base64 --help >/dev/null 2>&1; then
        ENC_KEY=$(head -c 32 /dev/urandom | base64 -w0)
    else
        ENC_KEY=$(head -c 32 /dev/urandom | base64 | tr -d '\n')
    fi

    CONFIG_FILE="${ENC_DIR}/encryption-config-${CLUSTER_NAME}.yaml"

    cat > "${CONFIG_FILE}" <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: ${ENC_KEY}
  - identity: {}
EOF

    # Minikube always looks for this filename
    cp "${CONFIG_FILE}" "${ENC_DIR}/encryption-config.yaml"

    POD_CIDR="10.${POD_CIDR_INDEX}.0.0/16"

    echo "Pod CIDR: ${POD_CIDR}"
    echo "Encryption config: ${CONFIG_FILE}"

    minikube delete -p "${CLUSTER_NAME}" >/dev/null 2>&1 || true

    minikube start \
        -p "${CLUSTER_NAME}" \
        --driver=docker \
        --network-plugin=cni \
        --cni=false \
        --extra-config=kubeadm.skip-phases=addon/kube-proxy \
        --extra-config=kubeadm.pod-network-cidr="${POD_CIDR}" \
        --extra-config=apiserver.encryption-provider-config=/var/lib/minikube/enc/encryption-config.yaml \
        --mount \
        --mount-string="${ENC_DIR}:/var/lib/minikube/enc"

    echo
    echo "Verifying mount..."

    minikube ssh -p "${CLUSTER_NAME}" -- \
        "ls -l /var/lib/minikube/enc && \
         echo && \
         cat /var/lib/minikube/enc/encryption-config.yaml"

    echo
    echo "[SUCCESS] ${CLUSTER_NAME} created."

    POD_CIDR_INDEX=$((POD_CIDR_INDEX + 1))

done

echo
echo "========================================================="
echo "All clusters created successfully."
echo "========================================================="
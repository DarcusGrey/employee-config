#!/bin/bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

CLUSTERS=("cluster1" "cluster2")
POD_CIDR_INDEX=244

# -----------------------------------------------------------------------------
# Create clusters
# -----------------------------------------------------------------------------

for CLUSTER_NAME in "${CLUSTERS[@]}"; do

    echo
    echo "========================================================="
    echo "Creating ${CLUSTER_NAME}"
    echo "========================================================="

    POD_CIDR="10.${POD_CIDR_INDEX}.0.0/16"
    echo "Pod CIDR: ${POD_CIDR}"

    # Ensure a clean slate by deleting any existing cluster with this name
    minikube delete -p "${CLUSTER_NAME}" >/dev/null 2>&1 || true

    # Start the cluster natively configured for Cilium
    minikube start \
        -p "${CLUSTER_NAME}" \
        --driver=docker \
        --container-runtime=docker \
        --network-plugin=cni \
        --cni=false \
        --extra-config=kubeadm.skip-phases=addon/kube-proxy \
        --extra-config=kubeadm.pod-network-cidr="${POD_CIDR}"

    echo
    echo "[SUCCESS] ${CLUSTER_NAME} created."

    # Increment the subnet for the next cluster (e.g., 244 -> 245)
    POD_CIDR_INDEX=$((POD_CIDR_INDEX + 1))

done

docker network connect cluster1 cluster2 2>/dev/null || true
docker network connect cluster2 cluster1 2>/dev/null || true

echo
echo "========================================================="
echo "All clusters created successfully. Ready for Cilium!"
echo "========================================================="
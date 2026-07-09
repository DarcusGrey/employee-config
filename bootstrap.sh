#!/bin/bash

# ==========================================
# 0. Configuration Variables
# ==========================================
PRIMARY_CTX="cluster1"
OTHER_CLUSTERS=("cluster2") # Array of secondary clusters
CLUSTER=$PRIMARY_CTX        # Alias used for primary setup
ID=1                        # Starting Cluster ID

# ==========================================
# Prerequisites Installation
# ==========================================
# Check if ArgoCD CLI is installed, if not, install it
if ! command -v argocd &> /dev/null; then
    echo "⏳ ArgoCD CLI not found. Installing..."
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64
    echo "✅ ArgoCD CLI installed successfully."
else
    echo "ArgoCD CLI is already installed. Skipping installation."
fi

# Check if helm is installed, if not, install it
if ! command -v helm &> /dev/null; then
    echo -e "\n⏳ Downloading and installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh
    echo "✅ Helm installed successfully."
else
    echo "Helm is already installed. Skipping installation."
fi

# ==========================================
# 1. Install Gateway API CRDs
# ==========================================
echo -e "\n📦 Installing Gateway API CRDs..."
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml --context ${CLUSTER}

# ==========================================
# 2. Install Primary CNI
# ==========================================
echo -e "\n🕸️ Installing Cilium CNI on ${CLUSTER}..."
helm repo add cilium https://helm.cilium.io/ 2>/dev/null
helm repo update

helm upgrade --install cilium cilium/cilium \
  --kube-context ${CLUSTER} \
  --namespace kube-system \
  --set cluster.name="${CLUSTER}" \
  --set cluster.id=${ID} \
  --set ipam.mode="kubernetes" \
  --set operator.replicas=1 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(minikube ip -p ${CLUSTER}) \
  --set k8sServicePort=8443 \
  --set envoy.enabled=true \
  --set gatewayAPI.enabled=true \
  --set clustermesh.useAPIServer=true \
  --set clustermesh.config.enabled=true \
  --set clustermesh.apiserver.service.type=NodePort \
  --wait

# Increment ID for the next cluster
ID=$((ID + 1))

# ==========================================
# 3. Extract Primary CA
# ==========================================
echo -e "\n🔑 Extracting Native CA from $PRIMARY_CTX..."
CA_CRT=$(kubectl get secret cilium-ca -n kube-system --context $PRIMARY_CTX -o jsonpath='{.data.ca\.crt}')
CA_KEY=$(kubectl get secret cilium-ca -n kube-system --context $PRIMARY_CTX -o jsonpath='{.data.ca\.key}')

if [ -z "$CA_CRT" ] || [ -z "$CA_KEY" ]; then
    echo "❌ Failed to extract CA from $PRIMARY_CTX. Exiting."
    exit 1
fi

# ==========================================
# 4. Patch CoreDNS on Primary
# ==========================================
echo -e "\n🔧 Patching CoreDNS on $PRIMARY_CTX..."
kubectl get configmap coredns -n kube-system --context ${CLUSTER} -o yaml | \
sed 's/forward . \/etc\/resolv.conf/forward . 8.8.8.8/' | \
kubectl apply --context ${CLUSTER} -f -

# ==========================================
# Secondary Clusters Setup Loop
# ==========================================
for CLSTR in "${OTHER_CLUSTERS[@]}"; do
    
    echo -e "\n💉 Injecting Master CA into Secondary ($CLSTR)..."
    cat <<EOF | kubectl apply --context $CLSTR -f -
apiVersion: v1
kind: Secret
metadata:
  name: cilium-ca
  namespace: kube-system
type: Opaque
data:
  ca.crt: ${CA_CRT}
  ca.key: ${CA_KEY}
EOF

    echo -e "\n🕸️ Installing Cilium on Secondary ($CLSTR)..."
    helm upgrade --install cilium cilium/cilium \
      --kube-context ${CLSTR} \
      --namespace kube-system \
      --set cluster.name="${CLSTR}" \
      --set cluster.id=${ID} \
      --set ipam.mode="kubernetes" \
      --set operator.replicas=1 \
      --set kubeProxyReplacement=true \
      --set k8sServiceHost=$(minikube ip -p ${CLSTR}) \
      --set k8sServicePort=8443 \
      --set envoy.enabled=true \
      --set gatewayAPI.enabled=true \
      --set clustermesh.useAPIServer=true \
      --set clustermesh.config.enabled=true \
      --set clustermesh.apiserver.service.type=NodePort \
      --wait

    ID=$((ID + 1))
done

# ==========================================
# 5. Install ArgoCD Server on Primary
# ==========================================
echo -e "\n🐙 Installing ArgoCD Server on ${CLUSTER}..."
kubectl create namespace argocd --dry-run=client -o yaml --context ${CLUSTER} | kubectl apply -f - --context ${CLUSTER}
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --context ${CLUSTER}

# Wait for ArgoCD API server to be ready before deploying apps
echo -e "\n⏳ Waiting for ArgoCD Server to be ready..."
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=180s --context ${CLUSTER}
echo "✅ ArgoCD is up and running."

# ==========================================
# 6. Apply ApplicationSet
# ==========================================
echo -e "\n🚀 Applying ArgoCD Infrastructure configuration..."
kubectl apply -f argocd-infra.yaml --context ${CLUSTER}
echo -e "\n🎉 Deployment script finished successfully!"


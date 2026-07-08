    # 1. Install Gateway API CRDs
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml --context cluster1

kubectl get configmap coredns -n kube-system --context cluster1 -o yaml | \
  sed 's/forward . \/etc\/resolv.conf/forward . 8.8.8.8/' | \
  kubectl apply --context cluster1 -f -

helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium  --kube-context cluster1 --namespace kube-system   --set cluster.name="cluster1"   --set cluster.id=1   --set ipam.mode="kubernetes"   --set operator.replicas=1   --set kubeProxyReplacement=true   --set k8sServiceHost=$(minikube ip -p cluster1)   --set k8sServicePort=8443   --set envoy.enabled=true   --set gatewayAPI.enabled=true


# 2. Install ArgoCD CLI locally (only if not installed)
if ! command -v argocd &> /dev/null; then
    echo "ArgoCD CLI not found. Installing..."
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64
    echo "ArgoCD CLI installed successfully."
else
    echo "ArgoCD CLI is already installed. Skipping installation."
fi

# 3. Install ArgoCD Server to Cluster 1
kubectl create namespace argocd --dry-run=client -o yaml --context cluster1 | kubectl apply -f - --context cluster1
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --context cluster1

# 4. Apply your ApplicationSet so ArgoCD deploys Cilium to your clusters
kubectl apply -f argocd-infra.yaml --context cluster1


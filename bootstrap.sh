kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml

helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium   --namespace kube-system   --set cluster.name="my-cluster"   --set cluster.id=1   --set ipam.mode="kubernetes"   --set operator.replicas=1   --set kubeProxyReplacement=true   --set k8sServiceHost=$(minikube ip)   --set k8sServicePort=8443   --set envoy.enabled=true   --set gatewayAPI.enabled=true

kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


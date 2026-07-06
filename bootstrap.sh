    # 1. Install Gateway API CRDs
    kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml


    # 2. Install ArgoCD CLI locally
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64

    # 3. Install ArgoCD Server to Cluster 1
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    # 4. Apply your ApplicationSet so ArgoCD deploys Cilium to your clusters
    kubectl apply -f argocd-infra.yaml


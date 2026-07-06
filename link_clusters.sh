#!/bin/bash
# link-clusters.sh

echo "Fetching Token from Cluster 2..."
TOKEN=$(kubectl get secret argocd-manager-long-lived-token -n kube-system --context cluster2 -o jsonpath='{.data.token}' | base64 -d)

echo "Detecting Cluster 2 IP..."
CLUSTER2_IP=$(minikube ip -p cluster2)

echo "Linking Cluster 2 to ArgoCD on Cluster 1..."
cat <<EOF | kubectl apply --context minikube -f -
apiVersion: v1
kind: Secret
metadata:
  name: cluster2-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: cluster2
  server: https://${CLUSTER2_IP}:8443
  config: |
    {
      "bearerToken": "${TOKEN}",
        "tlsClientConfig": {
        "insecure": true
        }
    }
EOF

echo "Cluster successfully linked!"
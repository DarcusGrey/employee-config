#!/bin/bash
# link-clusters.sh

echo "1. Creating ArgoCD Service Account and Token on Cluster 2..."
cat <<EOF | kubectl apply --context cluster2 -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: argocd-manager
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-long-lived-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
EOF

# Give Kubernetes a second to populate the token data
sleep 2

echo "2. Fetching Token from Cluster 2..."
TOKEN=$(kubectl get secret argocd-manager-long-lived-token -n kube-system --context cluster2 -o jsonpath='{.data.token}' | base64 -d)

echo "3. Detecting Cluster 2 IP..."
CLUSTER2_IP=$(minikube ip -p cluster2)

echo "4. Linking Cluster 2 to ArgoCD on Cluster 1..."
# NOTE: Changed context from 'minikube' to 'cluster1'
cat <<EOF | kubectl apply --context cluster1 -f -
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
#!/bin/bash
# link-clusters.sh (ArgoCD Cluster Registration)

PRIMARY_CTX="cluster1"
SECONDARY_CTX="cluster2"

echo "=========================================================="
echo "🔗 Linking Secondary Cluster to ArgoCD"
echo "=========================================================="

echo "[1/3] Creating ArgoCD Service Account and Token on $SECONDARY_CTX..."
cat <<EOF | kubectl apply --context $SECONDARY_CTX -f -
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

echo -e "\n[2/3] Fetching Token and IP from $SECONDARY_CTX..."
TOKEN=$(kubectl get secret argocd-manager-long-lived-token -n kube-system --context $SECONDARY_CTX -o jsonpath='{.data.token}' | base64 -d)
CLUSTER2_IP=$(minikube ip -p $SECONDARY_CTX)

echo -e "\n[3/3] Linking $SECONDARY_CTX to ArgoCD on $PRIMARY_CTX..."
cat <<EOF | kubectl apply --context $PRIMARY_CTX -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SECONDARY_CTX}-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: ${SECONDARY_CTX}
  server: https://${CLUSTER2_IP}:8443
  config: |
    {
      "bearerToken": "${TOKEN}",
      "tlsClientConfig": {
        "insecure": true
      }
    }
EOF

echo -e "\n✅ ArgoCD successfully linked to $SECONDARY_CTX!"
echo "ArgoCD is now ready to deploy your Layer 7 Application manifests to both clusters."


echo "Connecting Cluster Mesh..."
cilium clustermesh connect --context cluster1 --destination-context cluster2 
echo "Cluster successfully linked!"

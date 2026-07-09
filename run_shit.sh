bash start-cluster.sh
bash bootstrap.sh
bash link-clusters.sh
kubectl -n argocd --context cluster1 get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
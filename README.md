# Kubernetes Local Development Guide

## Step 0: Basics

Any YAML file can be applied with:
```bash
kubectl apply -f file.yaml -n <namespace>
```

To remove any component:
```bash
kubectl delete -f file.yaml -n <namespace>
kubectl delete <component-name> -n <namespace>
```

> **Note:** You cannot remove pods directly. You need to remove the **deployments** managing them — otherwise the deployment will immediately spin up a replacement pod.
> Sometimes you need to delete a component before re-applying it if you've made modifications.

View all active components in a namespace:
```bash
kubectl get all -n <namespace>
```

This doesn't include every component type. To see others:
```bash
kubectl get ns
kubectl get pvc
kubectl get gateway
```

### Debugging

Check how many replicas are ready. Common issues:
- **`ImagePullBackOff`** — likely an incorrect image tag
- **`CrashLoopBackOff`** — likely a problem with the command inside the container; also check that ports are configured correctly

Useful debugging commands:
```bash
kubectl get all -n <namespace>
kubectl describe <component-name> -n <namespace>
kubectl logs <component-name> -n <namespace>

# If the pod has multiple containers
kubectl logs <component-name> -c <container-name> -n <namespace>
```

You can also open the Minikube dashboard:
```bash
minikube dashboard --url
```

---

## Step 1: Setting Up Minikube

Minikube is a single-node cluster. For multi-node setups, use [kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker). Minikube requires the Docker engine to be running.

```bash
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64
minikube start

# Or start with custom resource limits
minikube start --cpus=4 --memory=8192

minikube status
```

---

## Step 2: Creating a Namespace

```bash
kubectl create ns employee
```

Install `kubectx` to easily manage contexts and namespaces:
```bash
sudo apt install kubectx
kubectl get ns
```

You can also define a namespace in `employee-chart/templates/namespace.yaml`, or use `--create-namespace` when running a command to create one if it doesn't exist.

> **Note:** There is no `namespace.yaml` in this repo and it is not defined in `values.yaml` because ArgoCD manages the namespace on its own.

To set the default namespace (avoids needing `-n employee` on every command):
```bash
kubens employee
```

---

## Step 3: Installing and Setting Up Helm

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

Create a new Helm chart:
```bash
helm create employee-chart
```

This creates an `employee-chart/` folder with `charts/` and `templates/`. The `templates/` folder includes pre-built templates for services, ingress, etc. You can use those templates and modify `values.yaml`, or wipe `templates/` and build from scratch.

Deploy, upgrade, or remove the chart:
```bash
helm install employee-app ./employee-chart -n employee
helm upgrade employee-app ./employee-chart -n employee
helm uninstall employee-app -n employee
```

> **Tip:** In `values.yaml`, if two different fields share the same value (e.g., `containerPort` and `targetPort`), that's intentional — labels and port mappings need to match.

---

## Step 4: Setting Up the Gateway API

Ingress has been the traditional approach for external traffic, but it has stopped receiving new features and its most popular controller has been deprecated. It has been succeeded by the **Gateway API**, which is more powerful but more complex.

Install the Gateway API CRDs:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/latest/download/standard-install.yaml
kubectl get crds | grep gateway
```

The Gateway API requires three resources:

### Gateway Controller
The actual implementation that processes routing rules. This guide uses the Envoy Gateway:
```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.5.9 \
  -n envoy-gateway-system \
  --create-namespace \
  --skip-crds

kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
```

### GatewayClass
A cluster-scoped resource that defines a template for Gateways. It tells the cluster which controller (e.g., Envoy) will implement Gateways of this class.
```bash
touch employee-chart/templates/gatewayclass.yaml
```

### Gateway
Represents the actual instantiated load balancer or proxy. Defines listening ports, protocols, and binds to infrastructure provisioned by the controller.
```bash
touch employee-chart/templates/gateway.yaml
```

### HTTPRoute
Defines specific rules for routing HTTP traffic. Attaches to a Gateway and forwards requests to the appropriate Kubernetes Service based on hostnames, paths, or headers.
```bash
touch employee-chart/templates/httproute.yaml
```

---

## Step 5: Creating the Server

```bash
touch employee-chart/templates/server.yaml
```

The `server.yaml` file defines three components:

### Deployment
The most basic Kubernetes component — Deployments manage ReplicaSets, which in turn manage Pods.

The Deployment pulls a container image from Docker Hub. For private repositories, you'll need to configure image pull credentials.

To use a **local Docker image** instead, set `imagePullPolicy: Never` and load the image into Minikube:
```bash
minikube image load employee-app:latest

# Verify the image is loaded
minikube ssh -- docker images
```

> **Note:** Avoid using the `latest` tag in production — it's prone to unexpected breakage. Use a specific version tag like `0.2`.

### Service
A LoadBalancer Service automatically routes traffic to all pods matching the configured label selector. Use `minikube tunnel` to expose the LoadBalancer externally.

```bash
# Assign an external address to the LoadBalancer
minikube tunnel

# Get the URL for testing
minikube service server-service --url
```

### HorizontalPodAutoscaler (HPA)
The HPA attaches to an existing Deployment and scales replicas automatically based on metrics like CPU usage or request count. The `minReplicas` and `maxReplicas` values in the HPA take precedence over those in the Deployment.

> **Note:** It is generally not recommended to scale on memory, as memory is not always released immediately.

---

## Step 6: Creating the Database

```bash
touch employee-chart/templates/database.yaml
```

> **Note:** For production, it is strongly recommended to use an **external database** rather than one inside the cluster, to prevent data loss if the cluster goes down.

### StatefulSet
Unlike Deployments (which are stateless), databases require a StatefulSet. Pods in a StatefulSet are assigned fixed names and ordering (e.g., `db-0`, `db-1`) — by default, `db-1` is only created after `db-0` is ready, though this can be made parallel.

When running multiple database replicas, write conflicts must be handled explicitly. A common pattern: only one pod is allowed to write, and the others sync from it. New pods copy data from the previous pod (e.g., `db-2` copies from `db-1`). Kubernetes operators exist to automate database synchronization.

This setup uses a Postgres image. Credentials (username, password, database name, etc.) are read from a Kubernetes Secret.

### Persistent Volume Claim (PVC)
A PVC is used to claim a fixed amount of storage for the StatefulSet, ensuring data persists even if the cluster restarts.

### Headless Service
A Headless Service is used to allow direct connections to the database pod, bypassing the usual load-balancing layer.

---

## Step 7: Secrets and ConfigMap

**Secrets** store sensitive values like passwords and private keys. **ConfigMaps** store non-sensitive configuration. ConfigMap values are managed via `values.yaml` in Helm rather than a separate `configmap.yaml`.

> **Important:** `secrets.yaml` is **not committed** to this repository because it contains sensitive data. Instead, **Sealed Secrets** are used to encrypt secrets before storing them.

### Setting Up Sealed Secrets

**Install kubeseal:**
```bash
curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.37/kubeseal-0.37-linux-amd64.tar.gz"
tar -xvzf kubeseal-0.37.0-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

**Install the Sealed Secrets controller:**
```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm install sealed-secrets sealed-secrets/sealed-secrets \
  -n kube-system \
  --create-namespace
```

### Create Your Secret Template

Create `employee-chart/templates/secrets.yaml`:
```yaml
{{- if .Values.sealingSecret}}
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Values.secretName }}
type: Opaque
stringData:
  DB_USER: db_username
  DB_PASS: db_password
  DB_NAME: {{ .Values.database.appName }}
  DB_URL: jdbc:postgresql://{{ .Values.database.svcName }}:5432/{{ .Values.database.appName }}
{{- end}}
```

### Seal the Secret

Fetch the public certificate (safe to commit to GitHub):
```bash
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  > sealed-secrets-cert.pem
```

Render the Helm template to produce a plain `secret.yaml` (do **not** commit this):
```bash
helm template employee-app ./employee-chart --set sealingSecret=true > secret.yaml
```

Seal it into a `SealedSecret` (safe to commit):
```bash
kubeseal \
  --cert sealed-secrets-cert.pem \
  -f secret.yaml -o yaml \
  > employee-chart/templates/sealed-secret.yaml
```

> **Note:** You may see a warning that the secret is empty. As long as `sealed-secret.yaml` contains encrypted versions of all fields from `secrets.yaml`, it is working correctly.

> **Important:** The public key is tied to the cluster and namespace. When deploying to a production environment, regenerate the cert from that environment.

---

## Step 8: Setting Up ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Create `argocd.yaml` to define your application as infrastructure-as-code, using this repository as the single source of truth:
```bash
touch argocd.yaml
```

Apply it:
```bash
kubectl apply -f argocd.yaml
```

### Accessing the ArgoCD Dashboard

```bash
kubectl port-forward svc/argocd-server -n argocd 8090:443
```

Open [https://127.0.0.1:8090](https://127.0.0.1:8090) in your browser.

- **Username:** `admin`
- **Password:**
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d; echo
  ```

If any services show their external connection as **Progressing**, assign an address with:
```bash
minikube tunnel
```

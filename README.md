# Kubernetes Local Development Guide

## Step 0: Basics

Any YAML file can be applied with:

```bash
kubectl apply -f file.yaml -n <namespace>
```

To remove any component:

```bash
kubectl delete -f file.yaml -n <namespace>
kubectl delete <component-type> <component-name> -n <namespace>
```

> **Note:** You can remove pods directly but that is only temporary removal. You need to remove the **deployments** managing them — otherwise the deployment will immediately spin up a replacement pod.
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
kubectl describe <component-type> <component-name> -n <namespace>
kubectl logs <component-type>/<component-name> -n <namespace>

# If the pod has multiple containers in a pod
kubectl logs pod/<component-name> -c <container-name> -n <namespace>
```

You can also open the Minikube dashboard:

```bash
minikube dashboard --url
```

---

## Step 1: Setting Up Minikube

Minikube is a single-node cluster. For multi-node setups, use [kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker). Minikube requires the Docker engine to be running. We are going to use cilium as our CNI so you need to start kubernetes with cni set as cilium.

```bash
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64
minikube start --cni=cilium

# Or start with custom resource limits
minikube start --cpus=4 --memory=8192 --cni=cilium

minikube status
```

---

## Step 2: Creating a Namespace

```bash
kubectl create ns employee
kubectl get ns
```

To set the default namespace (avoids needing `-n employee` on every command). Kubens is packaged with kubectx:

```bash
sudo apt install kubectx
kubens employee
```

You can also define a namespace in `employee-chart/templates/namespace.yaml`, or use `--create-namespace` when running a command to create one if it doesn't exist.

> **Note:** There is no `namespace.yaml` in this repo and it is not defined in `values.yaml` because ArgoCD manages the namespace on its own.

---

## Step 3: Installing and Setting Up Helm

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
```

Create a new Helm chart:

```bash
helm create employee-chart
```

This creates an `employee-chart/` folder with `charts/` and `templates/`. The `templates/` folder includes pre-built templates for services, ingress, etc. You can use those templates and modify `values.yaml`, or wipe `templates/` and build from scratch.

Do not run this command if you are deploying with argoCD. You can deploy the command for testing. But you need to clean this up if you wish to deploy argoCD or otherwise there would be ownership conflicts. To Deploy, upgrade, or remove the chart (Do this only after step 7):

```bash
helm install employee-app ./employee-chart -n employee
helm upgrade employee-app ./employee-chart -n employee
helm uninstall employee-app -n employee
```

To run in different environments like dev or prod you can use

```bash
helm install employee-app ./employee-chart -f values-dev.yaml -n employee-dev --create-namespace
helm install employee-app ./employee-chart -f values-prod.yaml -n employee-prod --create-namespace
```

> **Tip:** In `values.yaml`, if two different fields share the same value (e.g., `containerPort` and `targetPort`), that's intentional — labels and port mappings need to match.

---

## Step 4: Setting Up the Gateway API

Ingress has been the traditional approach for external traffic, but it has stopped receiving new features and its most popular controller (ingress-nginx) has been retired. It has been succeeded by the **Gateway API**, which is more powerful but more complex.

Install the Gateway API CRDs:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/latest/download/standard-install.yaml
kubectl get crds | grep gateway
```

There is an issue with cilium v1.19.xx. That it does not support gateway 1.5.x versions. This should be fixed with v1.20.xx of cilium, Till then the issue is that the TLSRoute CRD version provided by gateway 1.5 and the one expected by cilium do not match, So you have to manually install an older version of TLSRoute CRD to make it work, or user older gateway API version or wait for cilium 1.20 version.

```bash
kubectl delete validatingadmissionpolicybinding safe-upgrades.gateway.networking.k8s.io --ignore-not-found
kubectl delete validatingadmissionpolicy safe-upgrades.gateway.networking.k8s.io --ignore-not-found
kubectl delete crd gateways.gateway.networking.k8s.io gatewayclasses.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io referencegrants.gateway.networking.k8s.io grpcroutes.gateway.networking.k8s.io tlsroutes.gateway.networking.k8s.io --ignore-not-found
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/experimental-install.yaml

#If you have already started the cilium operator which is now in a degrated state, you need to restart it.
kubectl delete pod -n kube-system -l name=cilium-operator
```

The Gateway API requires three resources:

### GatewayClass

A cluster-scoped resource that defines a template for Gateways. It tells the cluster which controller (e.g., Envoy) will implement Gateways of this class.
This is not inside the helm chart system and is a clusterwide resource. This should be run only once whenever the cluster is set up.

```bash
touch gatewayclass.yaml

# Do this if you are using helm application, for argoCD we are going to use a different method.
# kubectl apply -f gatewayclass.yaml
```

### Gateway

Represents the actual instantiated load balancer or proxy. Defines listening ports, protocols, and binds to infrastructure provisioned by the controller.

```bash
touch employee-chart/templates/gateway.yaml
```

### HTTPRoute or TLSRoute

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

> **TODO:** This needs to be checked once, since there is a possibility that `minikube tunnel` and LoadBalancer will overwrite the gateway API set up. This has been acknowledged and should be fixed soon.

```bash
# Assign an external address to the LoadBalancer
minikube tunnel

# Get the URL for testing
minikube service server-service --url
```

### HorizontalPodAutoscaler (HPA)

The HPA attaches to an existing Deployment and scales replicas automatically based on metrics like CPU usage or request count. The `minReplicas` and `maxReplicas` values in the HPA take precedence over those in the Deployment.

> **Note:** It is generally not recommended to scale on memory, as memory is not always released immediately.
> **Note:** You can use external factors like http requests to trigger scaling, which requires external monitoring tools. In our case we are using cpu and memory which requires the minikube addon metric-server.

```bash
# Enable the addon metric-server to allow hpa scaling
minikube addons enable metrics-server
```

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

> **Important:** `secrets.yaml` is **not committed** to this repository because it contains sensitive data. Instead, **Sealed Secrets** are used to encrypt secrets before storing them. Also we are using `secret-values.yaml` as a secret storage in our case which is also **not committed**. Instead we are usng `secrets-template.yaml` which is just a template file with no sensitive information in the repository.

### Setting Up Sealed Secrets

**Install kubeseal (get the latest stable version from [the Sealed Secrets releases page](https://github.com/bitnami/sealed-secrets/releases)):**

```bash
curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.38.0/kubeseal-0.38.0-linux-amd64.tar.gz"
tar -xvzf kubeseal-0.38.0-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

**Install the Sealed Secrets controller:**

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install sealed-secrets bitnami/sealed-secrets -n kube-system --create-namespace
```

### Create Your Secrets Locally

Apart from the github repository you need to create a secrets folder with secrets as values. This will be useful for local sealed secret generation and would be not be used otherwise.

```bash
touch secrets/secret-values.yaml

#For dev/prod environment
touch secrets/secret-values-dev.yaml
```

In the `secret-values.yaml`, you need to write it in the form of a helm `values.yaml` file. Example of a `secret-values.yaml` file:

```yaml
secrets:
  username: db_username
  password: db_password

```

### Seal the Secret

Fetch the public certificate (safe to commit to GitHub):

```bash
kubeseal --fetch-cert --controller-name=sealed-secrets --controller-namespace=kube-system > sealed-secrets-cert.pem
```

Render the Helm template to produce a plain `secret_temp.yaml` (do **not** commit this):

```bash
helm template employee-app ./employee-chart -f secrets/secret-values.yaml --set sealingSecret=true -n employee --show-only templates/secrets_template.yaml > secret_temp.yaml

# Seal it into a `SealedSecret` (safe to commit):
kubeseal --cert sealed-secrets-cert.pem -f secret_temp.yaml -o yaml -n employee > sources/sealed-secrets.yaml
```

Creating secrets for dev/prod environment. Since dev/prod environment will work in a different namespace they need to have their secrets resealed. Replace `dev` with `prod` for prod.

```bash
helm template employee-app ./employee-chart   -f dev/values-dev.yaml   -f secrets/secret-values-dev.yaml  -n employee-dev --set sealingSecret=true --show-only templates/secrets_template.yaml > secret_temp.yaml

# Seal it into a `SealedSecret` (safe to commit):
kubeseal --cert sealed-secrets-cert.pem -f secret_temp.yaml -o yaml -n employee-dev > dev/sources/sealed-secrets-dev.yaml
```

> **Note:** You may see a warning that the secret is empty. As long as `sealed-secrets.yaml` contains encrypted versions of all fields from `secrets.yaml`, it is working correctly.
> **Important:** The public key is tied to the cluster and namespace. When deploying to a production environment, regenerate the cert from that environment.

Before running with helm make sure you have set up and run the cluster gateway class from step 3. This needs to be done once with cluster.

```bash
kubectl apply -f gatewayclass.yaml
```

Running with helm

```bash
helm install employee-app ./employee-chart -n employee

kubectl apply -f sources/sealed-secrets.yaml
```

For dev/prod environment. Replace `dev` with `prod` for prod.

```bash
helm install employee-app ./employee-chart -f dev/values-dev.yaml -n employee-dev --create-namespace

kubectl apply -f dev/sources/sealed-secrets-dev.yaml
```

---

## Step 8: Setting Up ArgoCD and Running

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Create `argocd.yaml` to define your application as infrastructure-as-code, using this repository as the single source of truth:

```bash
touch argocd.yaml
```

Apart from the `argocd.yaml` we are also using an `argocd-infra.yaml` to handle the cluster architecture. This `argocd-infra.yaml` should be applied before applying others.

```bash
kubectl apply -f argocd-infra.yaml

kubectl apply -f argocd.yaml
```

For different dev/prod environments use.

```bash
kubectl apply -f argocd-infra.yaml

kubectl apply -f dev/argocd-dev.yaml
```

### Accessing the ArgoCD Dashboard

```bash
kubectl port-forward svc/argocd-server -n argocd 8090:443
```

Open [https://127.0.0.1:8090](https://127.0.0.1:8090) in your browser.

- **Username:** `admin`
- **Password:**

  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
  ```

If any services show their external connection as **Progressing**, assign an address with:

```bash
minikube tunnel
```

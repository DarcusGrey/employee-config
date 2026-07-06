minikube start --network-plugin=cni   --cni=false   --extra-config=kubeadm.skip-phases=addon/kube-proxy

minikube start -p cluster2  --network-plugin=cni   --cni=false   --extra-config=kubeadm.skip-phases=addon/kube-proxy --extra-config=kubeadm.pod-network-cidr=10.245.0.0/16

minikube config

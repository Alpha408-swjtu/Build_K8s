#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "参数数量有误！"
    exit 1
fi

IP="$1"
Hostname="$2"

wget https://github.com/containerd/containerd/releases/download/v1.7.5/cri-containerd-1.7.5-linux-amd64.tar.gz
tar xf cri-containerd-1.7.5-linux-amd64.tar.gz  -C /
mkdir /etc/containerd
containerd config default > /etc/containerd/config.toml

sed -i 's/sandbox_image = "registry.k8s.io\/pause:3.8"/sandbox_image = "registry.aliyuncs.com\/google_containers\/pause:3.9"/g' /etc/containerd/config.toml
sed -i 's/SystemdCgroup =.*/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

echo "deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com B53DC80D13EDEF05
apt update

apt-get install kubeadm=1.24.1-00  kubelet=1.24.1-00 kubectl=1.24.1-00
apt-mark hold kubeadm kubelet kubectl

kubeadm config print init-defaults > kubeadm-config.yaml

sed -i "s/advertiseAddress:.*/advertiseAddress: ${IP}/" kubeadm-config.yaml
sed -i "s/name:.*/name: ${Hostname}/" kubeadm-config.yaml
sed -i 's/kubernetesVersion:.*/kubernetesVersion: 1.24.1/' kubeadm-config.yaml
sed -i 's/imageRepository:.*/imageRepository: registry.aliyuncs.com\/google_containers/' kubeadm-config.yaml
sed -i '/serviceSubnet/a\
  podSubnet: 10.244.0.0/16' kubeadm-config.yaml
sed -i '$a\
---\
kind: KubeletConfiguration\
apiVersion: kubelet.config.k8s.io/v1beta1\
cgroupDriver: systemd' kubeadm-config.yaml

systemctl restart containerd
systemctl restart kubelet

kubeadm config images pull --image-repository=registry.aliyuncs.com/google_containers --kubernetes-version v1.24.1
kubeadm init --config kubeadm-config.yaml
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#kubeadm token create --print-join-command
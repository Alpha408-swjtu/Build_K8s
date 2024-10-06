#!/bin/bash

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

systemctl restart containerd
systemctl restart kubelet
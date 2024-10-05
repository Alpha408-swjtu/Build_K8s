#!/bin/bash

#开启ipv4转发，并加载内核参数
cat << EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat << EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

#安装ipset和ipvsadm
apt-get install ipset ipvsadm

cat << EOF | tee /etc/modules-load.d/ipvs.conf
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF

cat << EOF | tee ipvs.sh
#!/bin/sh
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack
EOF

sh ipvs.sh

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
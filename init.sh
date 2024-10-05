#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "参数数量不对"
    exit 1
fi

ip="$1"
path="/etc/netplan/01-netconfig.yaml"
ctx=$(cat <<EOF
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: no
      addresses:
        - ${ip}/24
      gateway4: 192.168.32.2
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF
)

echo "$ctx" > "$path"

sed -i 's/cn.archive.ubuntu/mirrors.aliyun/g; s/security.ubuntu/mirrors.aliyun/g'  /etc/apt/sources.list
apt update
apt install net-tools vim open-vm-tools open-vm-tools-desktop openssh-server
sed -i 's/#Port 22/Port 22/g; s/#PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config

netplan apply
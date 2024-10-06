#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "参数数量不对"
    exit 1
fi

ip="$1"
gw="$2"
path="/etc/netplan/01-netconfig.yaml"

ctx=$(cat <<EOF
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: no
      addresses:
        - ${ip}/24
      gateway4: ${gw}
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF
)

echo "$ctx" > "$path"

#更换阿里云镜像源
sed -i 's/cn.archive.ubuntu/mirrors.aliyun/g; s/security.ubuntu/mirrors.aliyun/g'  /etc/apt/sources.list
apt update
apt install net-tools vim open-vm-tools open-vm-tools-desktop openssh-server
#开放ssh端口
sed -i 's/#Port 22/Port 22/g; s/#PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config

netplan apply
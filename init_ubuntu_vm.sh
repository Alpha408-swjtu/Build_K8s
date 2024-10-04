#!/bin/bash

su root
sed -i 's/cn.archive.ubuntu/mirrors.aliyun/g; s/securit.ubuntu/mirrors.aliyun/g'  /etc/apt/sources.list
apt update
apt install net-tools vim open-vm-tools open-vm-tools-desktop openssh_server
sed -i 's/#Port 22/Port 22/g; s/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
reboot

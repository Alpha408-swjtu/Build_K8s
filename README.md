# k8s搭建（containerd）

基于containerd的k8s集群搭建

## （以下操作在master和node上都要执行！！！！！！！！！！）

```
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: no
      addresses:
        - 192.168.32.140/24
      gateway4: 192.168.32.2
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]

```



### 一.内核转发，网桥过滤配置

```shell
su root
#配置依赖模块到 /etc/modules-load.d/k8s.conf ，后期可开机自动加载
cat << EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

#本次使用
modprobe overlay
modprobe br_netfilter

#查看是否成功
lsmod | egrep "overlay"
lsmod | egrep "br_netfilter"

#把网桥过滤和内核转发追加到k8s.conf文件中
cat << EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

#加载内核参数
sysctl --system

#看下内核的路由转发有没有成功打开
sysctl -a | grep ip_forward #net.ipv4.ip_forward=1说明成功
```

### 二. 安装ipset和ipvsadm

```shell
apt-get install ipset ipvsadm
#配置 ipvsadm 模块加载，添加需要加载的模块：（这样我们后续开机就可以自动加载了）
cat << EOF | tee /etc/modules-load.d/ipvs.conf
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF

#上面只是开机自动加载，但我们本次还需要用，所以我们本次要用的话可以将生效命令放到一个脚本文件中，然后执行
cat << EOF | tee ipvs.sh
#!/bin/sh
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack
EOF

#执行脚本文件
sh ipvs.sh

#看是否加载
lsmod | grep ip_vs

```

### 三.关闭swap分区

```shell
vim /etc/fstab
#找到 /swap.img none swap sw 0 0 这一行，给注释掉

#重启电脑
reboot
```

### 四.安装containerd

```shell
#下载安装包，要是因为github连不上，多执行几次或者科学上网
wget https://github.com/containerd/containerd/releases/download/v1.7.5/cri-containerd-1.7.5-linux-amd64.tar.gz

#解压安装包
tar xf cri-containerd-1.7.5-linux-amd64.tar.gz  -C /

#解压完就算安装完了。查看版本
containerd --version

#创建并修改配置文件
mkdir /etc/containerd
containerd config default > /etc/containerd/config.toml

ls /etc/containerd #看有没有成功

vim /etc/containerd/config.toml
#65行的 sanbox_image = "registry.k8s.io/pause:3.8" 改成 sandbox_image = "registry.aliyuncs.com/google_containers/pause:3.9"
#137行的 SystemdCgroup = false 改成 SystemdCgroup = true

#立即启动containerd
systemctl enable --now containerd

#看是否启动
systemctl status containerd
```

### 五.安装三件套

#### 1.软件准备

```shell
#使用阿里云的软件源
echo "deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

#看是否添加成功
ls /etc/apt/sources.list.d

#更新
apt-get update

#添加公钥
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com B53DC80D13EDEF05

#更新
apt-get update


```

#### 2.下载kubectl，kubeadm，kubelet

```shell
#查看可安装的版本
apt-cache madison kubeadm
apt-cache madison kubelet
apt-cache madison kubectl

#选自己要的版本安装。以1.28.1为例
apt-get install kubeadm=1.24.1-00  kubelet=1.24.1-00 kubectl=1.24.1-00

#查看版本，是否安装成功
kubeadm version
kubelet --version
kubectl version

#组织自动更新版本
apt-mark hold kubeadm kubelet kubectl
```

## 以下操作分别在master和node上执行！！！！具体见下

**master操作**

### 六.集群初始化

```shell
#将具体配置写入指定文件
kubeadm config print init-defaults > kubeadm-config.yaml

#编辑文件
vim kubeadm-config.yaml
#advertiseaddress改成master机的ip地址！！！！
#name改成master机的名字！！！！！
#kubernetesVersion改成对应版本！！！！！！！我的是1.24.1，根据之前三件套的版本改成自己的
#imageRepository改成registry.aliyuncs.com/google_containers
#配置网段，在 networking 中的 serviceSubnet 后面加上 podSubnet: 10.244.0.0/16，这个不能忘记，后面要用！！！！！！！！！！！
#在文件最后加入下方配置：
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd

#三台主机都要！！！！重启containerd和kubelet！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！！
systemctl restart containerd
systemctl restart kubelet

继续回到master 只在master操作！！！！！
#拉去初始化之前需要的镜像
kubeadm config images pull --image-repository=registry.aliyuncs.com/google_containers --kubernetes-version v1.24.1

#集群初始化。执行完后看见successful说明成功
kubeadm init --config kubeadm-config.yaml

#执行成功后输出下方三条指令，直接执行即可
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#此时先不要再master上操作！！！！！！初始化成功后，输出了一串代码，在then you can join any 。。。。这句话的后面，是kubeadm join xxxxx，复制它！！！
```

**node操作**

```shell
#将在master赋值的那一串，粘贴在node，运行
kubeadm join 192.168.57.131:6443 --token abcdef.0123456789abcdef \
        --discovery-token-ca-cert-hash sha256:258af31f0ec6869ff04aede2ce13a852d4a113ba60aa5efb3e32256eedc211cd 
#这是我的！！！！别直接复制粘贴，复制你自己的！！！！

#会显示节点加入集群成功的话，说明成功，回到master操作
```

**master操作**

```shell
kubectl get nodes
#发现所有节点已经加入，但是都是notready
```

### 七.安装flannel插件

####  没有这个步骤，节点都是notready状态

**master操作**

```shell
vim kube-flannel.yaml

##加入以下内容

---
kind: Namespace
apiVersion: v1
metadata:
  name: kube-flannel
  labels:
    pod-security.kubernetes.io/enforce: privileged
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: flannel
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes/status
  verbs:
  - patch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: flannel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- kind: ServiceAccount
  name: flannel
  namespace: kube-flannel
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flannel
  namespace: kube-flannel
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: kube-flannel-cfg
  namespace: kube-flannel
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "vxlan"
      }
    }
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-flannel-ds
  namespace: kube-flannel
  labels:
    tier: node
    app: flannel
spec:
  selector:
    matchLabels:
      app: flannel
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values:
                - linux
      hostNetwork: true
      priorityClassName: system-node-critical
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni-plugin
       #image: flannelcni/flannel-cni-plugin:v1.1.0 for ppc64le and mips64le (dockerhub limitations may apply)
        image: docker.io/rancher/mirrored-flannelcni-flannel-cni-plugin:v1.1.0
        command:
        - cp
        args:
        - -f
        - /flannel
        - /opt/cni/bin/flannel
        volumeMounts:
        - name: cni-plugin
          mountPath: /opt/cni/bin
      - name: install-cni
       #image: flannelcni/flannel:v0.19.0 for ppc64le and mips64le (dockerhub limitations may apply)
        image: docker.io/rancher/mirrored-flannelcni-flannel:v0.19.0
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/10-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
       #image: flannelcni/flannel:v0.19.0 for ppc64le and mips64le (dockerhub limitations may apply)
        image: docker.io/rancher/mirrored-flannelcni-flannel:v0.19.0
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
            add: ["NET_ADMIN", "NET_RAW"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: EVENT_QUEUE_DEPTH
          value: "5000"
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
        - name: xtables-lock
          mountPath: /run/xtables.lock
      volumes:
      - name: run
        hostPath:
          path: /run/flannel
      - name: cni-plugin
        hostPath:
          path: /opt/cni/bin
      - name: cni
        hostPath:
          path: /etc/cni/net.d
      - name: flannel-cfg
        configMap:
          name: kube-flannel-cfg
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate


kubectl apply -f kube-flannel.yaml

##如果镜像拉不下来，更换镜像下载地址
sed -i 's/docker.io/docker.1panel.live/g' kube-flannel.yaml

##可选的下载地址还有
docker.chenby.cn
dockerhub.icu
docker.awsl9527.cn
dhub.kubesre.xyz
docker.anyhub.us.kg
##这几个网站时好时不好，要是一个不行就再换下一个试试
```

删除集群

```shell
sudo kubeadm reset --force

sudo rm -rf /etc/systemd/system/kubelet.service.d

sudo systemctl daemon-reload

sudo apt-get purge -y kubelet kubeadm kubectl

sudo apt-get autoremove --purge kubelet kubeadm kubectl

systemctl stop containerd && sudo systemctl disable containerd

sudo apt-get purge -y containerd containerd.io

sudo rm -rf /var/lib/{kubelet,kube-proxy,kube-apiserver,kube-scheduler,kube-controller-manager}

 sudo rm -rf /etc/kubernetes

sudo rm -rf ~/.kube

reboot

ps -ef | grep kube*
```

部署nginx

```shell
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: default
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: docker.1panel.live/library/nginx:latest
        ports:
        - containerPort: 80
```

```
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  # 名字必需与下面的 spec 字段匹配，并且格式为 '<名称的复数形式>.<组名>'
  name: redises.stable.example.com
spec:
  # 组名称，用于 REST API: /apis/<组>/<版本>
  group: stable.example.com
  # 列举此 CustomResourceDefinition 所支持的版本
  versions:
    - name: v1beta1
      # 每个版本都可以通过 served 标志来独立启用或禁止
      served: true
      # 其中一个且只有一个版本必需被标记为存储版本
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                image:
                  type: string
                port:
                  type: integer
                targetPort: 
                  type: integer
                password: 
                  type: string            
  # 可以是 Namespaced 或 Cluster
  scope: Namespaced
  names:
    # 名称的复数形式，用于 URL：/apis/<组>/<版本>/<名称的复数形式>
    plural: redises
    # 名称的单数形式，作为命令行使用时和显示时的别名
    singular: redis
    # kind 通常是单数形式的驼峰命名（CamelCased）形式。你的资源清单会使用这一形式。
    kind: Redis
    # shortNames 允许你在命令行使用较短的字符串来匹配资源
    shortNames:
    - rd
```

crd.yaml

redis.yaml

```
apiVersion: stable.example.com/v1beta1
kind: Redis
metadata: 
  name: redis-cluster
spec: 
  image: xxx.latest
  port: 6379
  targetPort: 16379
  password: xxx
```


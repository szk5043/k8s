# 使用kubeadm安装k8s集群
## 一、环境
### 1、安装步骤
1. 在所有节点安装Docker和kubeadm
1. 部署Kubernetes Master
1. 部署容器网络插件
1. 部署kubernetes Worker
1. 部署Dashboard可视化插件
1. 部署容器存储插件

### 2、环境规划
本次安装测试环境的作业系统采用 `Ubuntu 16.04 Server`，其他细节内容如下：

| IP Address      | Role        | CPU  | Memory |
| --------------- | ------------| ---- | ------ |
| 192.168.8.155 | master         | 2    | 4G    |
| 192.168.8.156 | node1         | 2    | 4G     |
| 192.168.8.157 | node2         | 2    | 4G     |
> ubuntu16.04可以安装docker-ce 17.03，k8s1.11支持的最新docker版本17.03

### Hosts配置
配置每台主机的hosts(/etc/hosts),添加host_ip $hostname到/etc/hosts文件中
```
$ cat >> /etc/hosts << EOF
192.168.8.155 k8s-master
192.168.8.156 k8s-node1
192.168.8.157 k8s-node2
EOF
```

### Ubuntu\Debian系统下，默认cgroups未开启swap account功能
Ubuntu\Debian系统下，默认cgroups未开启swap account功能，这样会导致设置容器内存或者swap资源限制不生效。可以通过以下命令解决:
```
sudo sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1  /g'  /etc/default/grub
sudo update-grub
```
> 以上配置完成后，建议重启一次主机 

### 关闭swap分区
```
swapoff -a
```

### 添加apt源
```
cp /etc/apt/sources.list /etc/apt/sources.list.bak

cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/ubuntu/ xenial main
deb-src http://mirrors.aliyun.com/ubuntu/ xenial main

deb http://mirrors.aliyun.com/ubuntu/ xenial-updates main
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-updates main

deb http://mirrors.aliyun.com/ubuntu/ xenial universe
deb-src http://mirrors.aliyun.com/ubuntu/ xenial universe
deb http://mirrors.aliyun.com/ubuntu/ xenial-updates universe
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-updates universe

deb http://mirrors.aliyun.com/ubuntu/ xenial-security main
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-security main
deb http://mirrors.aliyun.com/ubuntu/ xenial-security universe
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-security universe
EOF
```

### 3、添加docker和kubernetes源为aliyun(所有机器)
```
apt-get update && apt-get install -y apt-transport-https

curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
#安装证书(阿里docker镜像源)

sudo add-apt-repository \
   "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
#安装镜像源(阿里docker镜像源)

curl https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add - 

cat  > /etc/apt/sources.list.d/kubernetes.list << EOF
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
```
### 4、安装指定版本的kubeadm(所有机器)
```
apt-get update
apt-cache madison kubeadm   
# 查看可安装的kubeadm版本或docker版本
apt-get install -y docker-ce=17.03.3~ce-0~ubuntu-xenial  kubeadm=1.11.1-00  kubelet=1.11.1-00 kubectl=1.11.1-00 kubernetes-cni --allow-downgrades
# --allow-downgrades允许降级安装
```
> 在上述安装kubeadm的过程中，kubeadm和kebelet、kubectl、kubernetes-cni这几个二进制文件都会被自动安装好

### 5、初始化master节点
#### 5.1 国内无法拉取官方镜像方法一：.1.13初始化成功，1.11初始化失败
将kubeadm 默认初始化配置打印到指定文件
```
kubeadm config print-default  > kubeadm.conf
# 1.13.0后命名为kubeadm config print init-defaults  > kubeadm.conf
```
由于gcr.io和quay.io国内无法访问，修改其镜像源为阿里云
```
sed -i "s/imageRepository: .*/imageRepository: registry.aliyuncs.com\/google_containers/g" kubeadm.conf
```
在kubeadm.conf中,添加对kube-controller-manager自动水平扩展配置
```
---
apiVersion: kubeadm.k8s.io/v1alpha2
kind: MasterConfiguration
controllerManagerExtraArgs:
  horizontal-pod-autoscaler-use-rest-clients: "true"
  horizontal-pod-autoscaler-sync-period: "10s"
  node-monitor-grace-period: "10s"
apiServerExtraArgs:
  runtime-config: "api/all=true"
```
使用阿里云镜像下载需要的镜像
```
kubeadm config images pull --config kubeadm.conf
```
初始化master节点
```
kubeadm init --config kubeadm.conf
```
#### 5.2 国内无法拉取官方镜像方法二，1.11初始化成功
用脚本下载阿里云镜像，并更改成gcr.io
```
cat > pullimages.sh << "EOF"
#!/bin/bash
K8S_VERSION="v1.11.1"
images=(kube-proxy-amd64:${K8S_VERSION} kube-scheduler-amd64:${K8S_VERSION} kube-controller-manager-amd64:${K8S_VERSION}
kube-apiserver-amd64:${K8S_VERSION} etcd-amd64:3.2.18 coredns:1.1.3 pause:3.1 )
for imageName in ${images[@]} ; do
  docker pull registry.aliyuncs.com/google_containers/$imageName
  docker tag registry.aliyuncs.com/google_containers/$imageName k8s.gcr.io/$imageName
  docker rmi registry.aliyuncs.com/google_containers/$imageName
done
EOF
```
在kubeadm.yaml中,添加对kube-controller-manager自动水平扩展配置
```
cat > kubeadm.yaml << EOF
apiVersion: kubeadm.k8s.io/v1alpha2
kind: MasterConfiguration
controllerManagerExtraArgs:
  horizontal-pod-autoscaler-use-rest-clients: "true"
  horizontal-pod-autoscaler-sync-period: "10s"
  node-monitor-grace-period: "10s"
apiServerExtraArgs:
  runtime-config: "api/all=true"
kubernetesVersion: "v1.11.1"
EOF
```
初始化master节点
```
kubeadm init --config kubeadm.yaml
```
#### 5.3 配置kubectl
默认会生成一个配置文件，需要拷贝到当前用户的家目录下，kubectl方可使用
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
配置kubectl shell自动补全
```
echo "source <(kubectl completion bash)" >> ~/.bashrc
source ~/.bashrc
```

### 6、Node节点加入集群
```
kubeadm join 192.168.8.155:6443 --token xxxx --discovery-token-ca-cert-hash sha256:xxxx
```
node节点下载镜像
```
cat > pullimages.sh << "EOF"
#!/bin/bash
K8S_VERSION="v1.11.1"
images=(kube-proxy-amd64:${K8S_VERSION} etcd-amd64:3.2.18 coredns:1.1.3 pause:3.1 )
for imageName in ${images[@]} ; do
  docker pull registry.aliyuncs.com/google_containers/$imageName
  docker tag registry.aliyuncs.com/google_containers/$imageName k8s.gcr.io/$imageName
  docker rmi registry.aliyuncs.com/google_containers/$imageName
done
EOF
```
### 7、查看集群状态
```
$ kubectl get nodes
NAME         STATUS     ROLES     AGE       VERSION
k8s-master   NotReady   master    3h        v1.11.1
k8s-node1    NotReady   <none>    2h        v1.11.1
k8s-node2    NotReady   <none>    2h        v1.11.1
# 发现都是NotReady状态

$ kubectl describe node k8s-master 
nNotReady message:docker: network plugin is not ready: cni config uninitialized
...
# 没有安装网络插件
```
### 8、安装网络插件
```
$ kubectl apply -f https://git.io/weave-kube-1.6
# node节点需要安装pause镜像，请使用5.1或者5.2下载
```
部署完成，查看相应pod状态
```
$ kubectl get pods -n kube-system 
NAME                                 READY     STATUS    RESTARTS   AGE
coredns-78fcdf6894-mcw2x             1/1       Running   0          8h
coredns-78fcdf6894-v5ctq             1/1       Running   0          8h
etcd-k8s-master                      1/1       Running   0          7h
kube-apiserver-k8s-master            1/1       Running   0          7h
kube-controller-manager-k8s-master   1/1       Running   0          7h
kube-proxy-7kg4c                     1/1       Running   0          8h
kube-proxy-9c694                     1/1       Running   0          7h
kube-proxy-tj5hw                     1/1       Running   0          7h
kube-scheduler-k8s-master            1/1       Running   0          7h
weave-net-2q9mj                      2/2       Running   0          5h
weave-net-d6h7p                      2/2       Running   5          5h
weave-net-dspzf                      2/2       Running   5          5h
```
### 9、部署dashboard可视化插件
```
$ kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml
```
需要手工下载镜像
```
docker pull registry.aliyuncs.com/google_containers/kubernetes-dashboard-amd64:v1.10.1
docker tag registry.aliyuncs.com/google_containers/kubernetes-dashboard-amd64:v1.10.1 k8s.gcr.io/kubernetes-dashboard-amd64:v1.10.1
docker rmi registry.aliyuncs.com/google_containers/kubernetes-dashboard-amd64:v1.10.1
```
默认不可访问，需要配置Ingress
```

```
[https://github.com/kubernetes/dashboard](https://github.com/kubernetes/dashboard)

### 10、安装容器存储插件
```
$ kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/cluster/examples/kubernetes/ceph/operator.yaml

$ kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/cluster/examples/kubernetes/ceph/cluster.yaml
```
查看相应的NameSpace和其中的pod
```
$ kubectl get pods -n rook-ceph-system
NAME                                  READY     STATUS    RESTARTS   AGE
rook-ceph-agent-fb5rm                 1/1       Running   0          9m
rook-ceph-agent-fft7t                 1/1       Running   0          9m
rook-ceph-operator-5496d44d7c-krgrm   1/1       Running   0          13m
rook-discover-ddp9l                   1/1       Running   0          9m
rook-discover-p7q75                   1/1       Running   0          9m

$ kubectl get pods -n rook-ceph
NAME                               READY     STATUS    RESTARTS   AGE
rook-ceph-mon-a-5d7ddb9876-n8rh6   1/1       Running   0          3m
rook-ceph-mon-d-fb6bc8c5-cg5ck     1/1       Running   0          1m
rook-ceph-mon-e-7ddb9d4fff-m7v8f   1/1       Running   0          27s
```

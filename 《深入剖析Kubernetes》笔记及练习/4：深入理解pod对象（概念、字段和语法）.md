## 深入理解pod对象
### 一、pod的理解
pod扮演传统虚拟机的角色：
网卡：Pod网络定义
磁盘：Pod的存储定义
防火墙：Pod的安全定义
运行在哪台物理机：Pod的调度定义

### 二、pod的重要字段和语法
  
**NodeSelector**：是一个供用户将Pod与Node进行绑定的字段
```
apiVersion: v1
kind: Pod
...
spec:
 nodeSelector:
   disktype: ssd
```
> 这个配置，意味着这个pod永远只能运行在携带"disktype:ssd"标签(Label)的节点上；否则调度失败。   

**NodeName**：一旦Pod的这个字段被复制，Kubernetes项目就会被认为这个Pod已经经过了调度，调度的结果就是赋值的节点名字。所以，这个字段一般由调度器负责设置，但用户也可以设置它来“骗过”调度器，当然这个做法一般是在测试或调试的时候才会用到。

**HostAliases**：定义了Pod的hosts文件(比如/etc/hosts)里的内容
```
apiVersion: v1
kind: Pod
...
spec:
  hostAliases:
  - ip: "10.1.2.3"
    hostnames:
    - "foo.remote"
    - "bar.remote"
...
```
这个Pod的yaml文件中，设置了一组IP和hostname的数据。这样，这个Pod启动后，/etc/hosts文件的内容将如下所示：
```
cat /etc/hosts
# Kubernetes-managed hosts file.
127.0.0.1 localhost
...
10.244.135.10 hostaliases-pod
10.1.2.3 foo.remote
10.1.2.3 bar.remote
```
> 需要指出，在Kubernetes项目中，如果需要设置hosts文件里的内容，一定要通过这种方式。否则，如果直接改了hosts文件的话，在Pod被删除重建之后，kebelt会自动覆盖掉被修改的内容。

**shareProcessNamespace**：这个字段设置为true，意味着这个Pod里的容器共享PID Namespace。   
定义一个Pod，配置两个容器：Nginx容器和开启tty和stdin的shell容器(等同于docker run 里的-it,-i即stdin,-t即tty参数)
```
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  shareProcessNamespace: true
  containers:
  - name: nginx
    image: nginx
  - name: shell
    image: busybox
    stdin: true
    tty: true
```
这个Pod创建好之后，可以使用shell容器的tty跟这个容器进行交互了
```
$ kubectl create -f nginx.yaml
$ kubectl attach -it nginx -c shell
```
这样，可以在shell容器里执行ps指令，查看所有正在运行的进程：
```
$ kubectl attach -it nginx -c shell
/ # ps ax
PID   USER     TIME  COMMAND
    1 root      0:00 /pause
    8 root      0:00 nginx: master process nginx -g daemon off;
   14 101       0:00 nginx: worker process
   15 root      0:00 sh
   21 root      0:00 ps ax
# 实验测试没法看到进程，仅能看到端口
```
[官方文档：在Pod中的容器之间共享进程命名空间](https://kubernetes.io/docs/tasks/configure-pod-container/share-process-namespace/)    
**hostNetwork**、**hostIPC**、**hostPID**：共享宿主机的Namespace，也是Pod级别的定义。
```
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  hostNetwork: true
  hostIPC: true
  hostPID: true
  containers:
  - name: nginx
    image: nginx
  - name: shell
    image: busybox
    stdin: true
    tty: true
```
> 在这个pod中，定义了共享宿主机的Network、IPC和PID Namespace。意味着，这个Pod里的所有容器，会直接使用宿主机的网络、直接与宿主机进行IPC通信，看到宿主机正在运行的所有进程。
```
$ kubectl attach -it nginx -c shell
/ # ps ax
PID   USER     TIME  COMMAND
    1 root      1:20 {systemd} /sbin/init
    2 root      0:00 [kthreadd]
    3 root      0:07 [ksoftirqd/0]
    5 root      0:00 [kworker/0:0H]
    7 root      0:42 [rcu_sched]
    8 root      0:00 [rcu_bh]
    9 root      0:01 [migration/0]
   10 root      0:00 [watchdog/0]
   ...
```
### 三、pod对容器级别定义的相关字段和语法
**init Containers**：Init Containers的生命周期，会先于所有的Containers，并且严格按照定义的顺序执行。类似docker-compose里的link字段。

**ImagePullPolicy**：定义镜像拉取的策略：
- Always：默认值，即每次创建Pod都重新拉取一次镜像。若镜像是nginx或nginx:latest这样的名字时，ImagePullPolicy也会被认为是Always。
- Never：Pod永远不会主动拉取这个镜像，只有当宿主机不存在这个镜像才会拉取。
- ifNotPresent：Pod永远不会主动拉取这个镜像，只有当宿主机不存在这个镜像才会拉取。 

[官方文档：镜像拉取的策略](https://kubernetes.io/docs/concepts/containers/images/)

**Lifecycle**：定义Containers Lifecycle Hooks。实在容器状态发生变化时触发一系列的“钩子”。
```
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-demo
spec:
  containers:
  - name: lifecycle-demo-container
    image: nginx
    lifecycle:
      postStart:
        exec:
          command: ["/bin/sh", "-c", "echo Hello from the postStart handler > /usr/share/message"]
      preStop:
        exec:
          command: ["/usr/sbin/nginx","-s","quit"]
```
> lifecycle定义了两个字段：postStart，在容器启动后，立即执行一个指定的操作。postStop，在容器被杀死之前，指定指定的操作。

### 四、Pod对象在Kubernetes中的生命周期
Pod的生命周期的变化，主要体现在Pod API对象的Status部分，这是它除了Metadata和Spec之外的第三个重要字段。其中，pod.status.phase，就是Pod的当前字段，它有如下几种可能的情况：   
***Pod status***:
- Pendin：这个状态意味着，Pod的YAML文件已经提交给了Kubernetes，API对象已经被创建保存在Etcd当中。但是，这个Pod里有些容器因为某种原因而不能顺利创建。比如，调度不成功。
- Running：这种状态下，Pod已经调度成功，跟一个具体的节点绑定。它包含的容器都已经创建成功，并且至少有一个正在运行中。
- Succeeded：这个状态意味着，Pod里的所有容器都正常运行完毕，并且已经退出了。这种情况在运行一次性任务时最为常见。
- Failed：这个状态下，Pod里至少有一个容器以不正常的状态（非0的返回码）退出。这个状态的出现，意味着得想办法debug这个容器的应用，比如查看Pod的Events和日志。
- Unkonwn：这是一个异常状态，意味着Pod的状态不能持续的被kubelet汇报给kube-apiserver，这很有可能是主从节点（Master和kubelet）间的通信出现了问题。

***Pod status conditions***:
- PodScheduled：调度中
- Ready：若Pod status为Running，conditions为Ready，容器可以提供服务。
- Initialized：初始化
- Unschedulable：无法调度

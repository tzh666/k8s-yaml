## 动态存储管理实战之GlusterFS

### 一、准备工作

- 在各个节点都安装上GFS客户端

  ```sh
  yum install glusterfs glusterfs-fuse -y
  ```

- GFS运行在k8s上需要特权模式

  ```sh
  # 如果没有加上即可
  ps -ef | grep kube-api | grep allow-privileged=true
  ```

- 给需要安装GFS管理服务的节点打上标签

  ```sh
  kubectl label nodes node01 storagenode=glusterfs
  kubectl label nodes node02 storagenode=glusterfs
  kubectl label nodes node03 storagenode=glusterfs
  ```

- 部署的GlusterFS节点有sdb裸盘

  ```sh
  sdb
  
  mkfs.xfs -f /dev/sdb
  ```

- 所有节点加载对应模块

  ```sh
  [root@k8s-master01 ~]# modprobe dm_snapshot
  [root@k8s-master01 ~]# modprobe dm_mirror
  [root@k8s-master01 ~]# modprobe dm_thin_pool
  
  cat >/etc/sysconfig/modules/glusterfs.modules <<EOF
  #!/bin/bash
  
  for kernel_module in dm_snapshot dm_mirror dm_thin_pool;do
      /sbin/modinfo -F filename ${kernel_module} > /dev/null 2>&1
      if [ $? -eq 0 ]; then
          /sbin/modprobe ${kernel_module}
      fi 
  done;
  EOF
  [root@kube-node1 ~]# chmod +x /etc/sysconfig/modules/glusterfs.modules
  
  # 检查 modprobe 是否加载成功
  [root@k8s-master01 ~]# lsmod | egrep  '(dm_snapshot|dm_mirror|dm_thin_pool)'
  dm_thin_pool           69632  0 
  dm_persistent_data     73728  1 dm_thin_pool
  dm_bio_prison          20480  1 dm_thin_pool
  dm_snapshot            40960  0 
  dm_bufio               28672  2 dm_persistent_data,dm_snapshot
  dm_mirror              24576  0 
  dm_region_hash         20480  1 dm_mirror
  dm_log                 20480  2 dm_region_hash,dm_mirror
  dm_mod                126976  13 dm_thin_pool,dm_log,dm_snapshot,dm_mirror,dm_bufio
  ```

  

### 二、创建GlusterFS管理服务容器集群

- 这都是官方的，是json格式的,如果看不习惯可以用我转换过来的yaml格式的文件创建集群

```sh
[root@master01 kubernetes]# wget https://github.com/heketi/heketi/releases/download/v7.0.0/heketi-client-v7.0.0.linux.amd64.tar.gz

[root@k8s-master01 GFS]#tar -xf heketi-client-v7.0.0.linux.amd64.tar.gz 
[root@master01 kubernetes]# ll
total 40
-rw-rw-r-- 1 1000 1000 5222 Jun  5  2018 glusterfs-daemonset.json
-rw-rw-r-- 1 1000 1000 3513 Jun  5  2018 heketi-bootstrap.json
-rw-rw-r-- 1 1000 1000 4113 Jun  5  2018 heketi-deployment.json
-rw-rw-r-- 1 1000 1000 1109 Jun  5  2018 heketi.json
-rw-rw-r-- 1 1000 1000  111 Jun  5  2018 heketi-service-account.json
-rwxrwxr-x 1 1000 1000  584 Jun  5  2018 heketi-start.sh
-rw-rw-r-- 1 1000 1000  977 Jun  5  2018 README.md
-rw-rw-r-- 1 1000 1000 1827 Jun  5  2018 topology-sample.json

# 到时候把/root/heketi-client/bin/heketi-cli copy到各个节点上
cp /root/heketi-client/bin/heketi-cli /usr/local/bin/heketi-cli
scp /root/heketi-client/bin/heketi-cli  node01:/usr/local/bin/heketi-cli
```

- 部署GlusterFS

```sh
kind: DaemonSet
apiVersion: apps/v1
metadata:
  name: glusterfs
  labels:
    glusterfs: daemonsett
  annotations:
    description: GlusterFS DaemonSet
    tags: glusterfs
spec:
  selector:
    matchLabels:
      glusterfs-node: pod
  template:
    metadata:
      name: glusterfs
      labels:
        glusterfs-node: pod
    spec:
      nodeSelector:
        storagenode: glusterfs
      hostNetwork: true
      containers:
      - image: gluster/gluster-centos:latest
        name: glusterfs
        volumeMounts:
        - name: glusterfs-heketi
          mountPath: "/var/lib/heketi"
        - name: glusterfs-run
          mountPath: "/run"
        - name: glusterfs-lvm
          mountPath: "/run/lvm"
        - name: glusterfs-etc
          mountPath: "/etc/glusterfs"
        - name: glusterfs-logs
          mountPath: "/var/log/glusterfs"
        - name: glusterfs-config
          mountPath: "/var/lib/glusterd"
        - name: glusterfs-dev
          mountPath: "/dev"
        - name: glusterfs-misc
          mountPath: "/var/lib/misc/glusterfsd"
        - name: glusterfs-cgroup
          mountPath: "/sys/fs/cgroup"
          readOnly: true
        - name: glusterfs-ssl
          mountPath: "/etc/ssl"
          readOnly: true
        securityContext:
          capabilities: {}
          privileged: true   # 特权模式
        readinessProbe:
          timeoutSeconds: 3
          initialDelaySeconds: 60
          exec:
            command:
            - "/bin/bash"
            - "-c"
            - systemctl status glusterd.service
        livenessProbe:
           timeoutSeconds: 3
           initialDelaySeconds: 60
           exec:
             command:
             - "/bin/bash"
             - "-c"
             - systemctl status glusterd.service
      volumes:
      - name: glusterfs-heketi
        hostPath:
          path: "/var/lib/heketi"
      - name: glusterfs-run
      - name: glusterfs-lvm
        hostPath:
          path: "/run/lvm"
      - name: glusterfs-etc
        hostPath:
          path: "/etc/glusterfs"
      - name: glusterfs-logs
        hostPath:
          path: "/var/log/glusterfs"
      - name: glusterfs-config
        hostPath:
          path: "/var/lib/glusterd"
      - name: glusterfs-dev
        hostPath:
          path: "/dev"
      - name: glusterfs-misc
        hostPath:
          path: "/var/lib/misc/glusterfsd"
      - name: glusterfs-cgroup
        hostPath:
          path: "/sys/fs/cgroup"
      - name: glusterfs-ssl
        hostPath:
          path: "/etc/ssl"
```

- 验证部署结果

```sh
[root@master01 GFS]# kubectl get po  -l glusterfs-node=pod -owide 
NAME              READY   STATUS    RESTARTS   AGE    IP             NODE     NOMINATED NODE   READINESS GATES
glusterfs-5qtd8   1/1     Running   0          5m4s   192.168.1.72   node02   <none>           <none>
glusterfs-h48vq   1/1     Running   0          5m4s   192.168.1.71   node01   <none>           <none>
glusterfs-jgm82   1/1     Running   0          5m4s   192.168.1.73   node03   <none>           <none>
```



### 三、创建Heketi服务

- Heketi是一个提供RESTful API 管理GFS卷的框架，能够在OpenStack、k8s、OpenShit等平台上实现动态存储资源供应，支持GFS多集群管理，便于管理员对GFS进行操作

#### 3.1、创建一个ServiceAccount、Role、RoleBinding（heketi-svc.yaml ）

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: heketi-service-account
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: heketi
  namespace: default
rules:
- apiGroups: [""]                   # 空字符串,表示 Core API Group
  resources: ["pods","services","endpoints"] # 这个Role只可以操作Pod\svc\ep,操作方式在下面的verbs[]
  verbs: ["get","watch","list"]
- apiGroups: [""]                   # 空字符串,表示 Core API Group
  resources: ["pods/exec"]         
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: heketi          # 
  namespace: default    # 权限仅在该ns下起作用
subjects:
- kind: ServiceAccount  # 类型是sa,说明这个sa有role为heketi的权限
  name: heketi-service-account
roleRef:                # 角色绑定信息 
  kind: Role            # 绑定的对象是角色,也可以是集群角色
  name: heketi          # 绑定的Role name
  apiGroup: rbac.authorization.k8s.io  # 默认
```

```sh
# 再创建个集群角色？这个应该是不用的，网上的狗屎博客
kubectl create clusterrole heketi-cr-tzh --verb=get,list,watch,create --resource=pods,pods/status,pods/exec
```



#### 3.2、部署Heketi服务

```yaml
kind: Deployment
apiVersion: apps/v1
metadata:
  name: deploy-heketi
  labels:
    glusterfs: heketi-deployment
    deploy-heketi: heket-deployment
  annotations:
    description: Defines how to deploy Heketi
spec:
  selector:
    matchLabels:
      glusterfs: heketi-pod
  replicas: 1
  template:
    metadata:
      name: deploy-heketi
      labels:
        glusterfs: heketi-pod
        name: deploy-heketi
    spec:
      serviceAccountName: heketi-service-account       # 使用这个SA
      containers:
      - image: heketi/heketi
        imagePullPolicy: IfNotPresent
        name: deploy-heketi
        env:
        - name: HEKETI_EXECUTOR
          value: kubernetes
        - name: HEKETI_FSTAB
          value: "/var/lib/heketi/fstab"
        - name: HEKETI_SNAPSHOT_LIMIT
          value: '14'
        - name: HEKETI_KUBE_GLUSTER_DAEMONSET
          value: "y"
        # - name: HEKETI_ADMIN_KEY # 如果用了这个 就这样创建heketi-cli -s $HEKETI_CLI_SERVER --user admin --secret admin123 topology load --json=topology.json
        #   value: "admin123"       # 这是下面连接要的密码可自行更改
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: db
          mountPath: "/var/lib/heketi"
        readinessProbe:
          timeoutSeconds: 3
          initialDelaySeconds: 3
          httpGet:
            path: "/hello"
            port: 8080
        livenessProbe:
          timeoutSeconds: 3
          initialDelaySeconds: 30
          httpGet:
            path: "/hello"
            port: 8080
      volumes:
      - name: db
        hostPath:
            path: "/heketi-data"
 
---
kind: Service
apiVersion: v1
metadata:
  name: deploy-heketi
  labels:
    glusterfs: heketi-service
    deploy-heketi: support
  annotations:
    description: Exposes Heketi Service
spec:
  selector:
    name: deploy-heketi
  ports:
  - name: deploy-heketi
    port: 8080
    targetPort: 8080
```

#### 3.3、通过Heketi创建GFS集群

- 需要三块裸盘
- 修改盘符、节点名字（一般都是主机名,kubectl get no 看看吧）、IP即可
- **topology.json**

```json
{
    "clusters": [
        {
            "nodes": [
                {
                    "node": {
                        "hostnames": {
                            "manage": [
                                "node01"
                            ],
                            "storage": [
                                "192.168.1.71"
                            ]
                        },
                        "zone": 1
                    },
                    "devices": [
                        "/dev/sdb"
                    ]
                },
                {
                    "node": {
                        "hostnames": {
                            "manage": [
                                "node02"
                            ],
                            "storage": [
                                "192.168.1.73"
                            ]
                        },
                        "zone": 1
                    },
                    "devices": [
                        "/dev/sdb"
                    ]
                },
                {
                    "node": {
                        "hostnames": {
                            "manage": [
                                "node03"
                            ],
                            "storage": [
                                "192.168.1.74"
                            ]
                        },
                        "zone": 1
                    },
                    "devices": [
                        "/dev/sdb"
                    ]
                }
            ]
        }
    ]
}
```

```sh
# http://10.105.206.233:8080 是svc IP 
[root@master01 GFS]# cd /root/k8s/k8s-yaml/volume/GFS
[root@master01 GFS]# heketi-cli -s http://10.105.206.233:8080 --user admin --secret admin123 topology load --json=topology.json
        Found node node01 on cluster 9e78d3c3197d865d633954fda463d454
                Adding device /dev/sdb ... Unable to add device: Initializing device /dev/sdb failed (already initialized or contains data?): WARNING: xfs signature detected on /dev/sdb at offset 0. Wipe it? [y/n]: [n]
  Aborted wiping of xfs.
  1 existing signature left on the device.
        Found node node02 on cluster 9e78d3c3197d865d633954fda463d454
                Adding device /dev/sdb ... Unable to add device: Initializing device /dev/sdb failed (already initialized or contains data?): WARNING: xfs signature detected on /dev/sdb at offset 0. Wipe it? [y/n]: [n]
  Aborted wiping of xfs.
  1 existing signature left on the device.
        Found node node03 on cluster 9e78d3c3197d865d633954fda463d454
                Adding device /dev/sdb ... Unable to add device: Initializing device /dev/sdb failed (already initialized or contains data?): WARNING: xfs signature detected on /dev/sdb at offset 0. Wipe it? [y/n]: [n]
  Aborted wiping of xfs.
  1 existing signature left on the device.
  
解决:进入节点glusterfs容器执行pvcreate -ff --metadatasize=128M --dataalignment=256K /dev/sdb


#  再次执行
[root@master01 GFS]# heketi-cli -s http://10.105.206.233:8080 --user admin --secret admin123 topology load --json=topology.json
        Found node node01 on cluster 9e78d3c3197d865d633954fda463d454
                Found device /dev/sdb
        Found node node02 on cluster 9e78d3c3197d865d633954fda463d454
                Adding device /dev/sdb ... OK
        Found node node03 on cluster 9e78d3c3197d865d633954fda463d454
                Found device /dev/sdb
```



### 四、测试

#### 4.1、创建StrongerClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gluster-heketi
provisioner: kubernetes.io/glusterfs
reclaimPolicy: Retain
parameters:
  resturl: "http://10.106.91.126:8080"
  restauthenabled: "true"
  restuser: "admin"
  restuserkey: "admin123"
  gidMin: "40000"
  gidMax: "50000"
  volumetype: "replicate:3"
allowVolumeExpansion: true
```

#### 4.2、创建Pod

```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pvc-gluster-heketi
spec:
  accessModes: [ "ReadWriteOnce" ]
  storageClassName: "gluster-heketi"
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-use-pvc
spec:
  containers:
  - name: pod-use-pvc
    image: busybox
    command:
      - sleep
      - "3600"
    volumeMounts:
    - name: gluster-volume
      mountPath: "/pv-data"
      readOnly: false
  volumes:
  - name: gluster-volume
    persistentVolumeClaim:
      claimName: pvc-gluster-heketi
```

#### 4.3、验证Pod是Running即可

```sh
[root@master01 kubernetes]# kubectl get po  pod-use-pvc
NAME          READY   STATUS    RESTARTS   AGE
pod-use-pvc   1/1     Running   0          3m46s
```


## NGINX Ingress Controller 安装（nginx官方维护的ingress）

### 一、Nginx-ingress的官方文档

```sh
https://docs.nginx.com/nginx-ingress-controller/configuration/ingress-resources/advanced-configuration-with-annotations/
```

### 二、Ingress安装

#### 2.1、首先安装helm管理工具

```shell
# 1、下载
[root@k8s-master01 ~]# wget https://get.helm.sh/helm-v3.4.2-linux-amd64.tar.gz

# 2、安装
[root@k8s-master01 ~]# tar -zxvf helm-v3.4.2-linux-amd64.tar.gz 
[root@k8s-master01 ~]# mv linux-amd64/helm /usr/local/bin/helm
```

#### 2.2、使用helm安装ingress

- 部署要注意的：
  - **nginx-ingress 所在的节点需要能够访问外网**，域名才可以解析到这些节点上直接使用
  - 需要让 nginx-ingress 绑定节点的 80 和 443 端口，所以可以使用 hostPort 来进行访问
  - 测试此处采用 hostNetwork 模式（**生产环境可以使用 LB + DaemonSet hostNetwork 模式）**
  - 当然对于线上环境来说为了保证高可用，一般是需要运行多个 nginx-ingress 实例
  - 然后可以用一个 nginx/haproxy 作为入口，通过 keepalived 来访问边缘节点的 vip 地址
- 边缘节点
  - 所谓的边缘节点**即集群内部用来向集群外暴露服务能力的节点**
  - **集群外部的服务通过该节点来调用集群内部的服务**
  - **边缘节点是集群内外交流的一个Endpoint**

```sh
# 1、添加ingress的helm仓库
[root@k8s-master01 ~]# helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
"ingress-nginx" has been added to your repositories

# 2、下载ingress的helm包至本地（helm pull ingress-nginx/ingress-nginx --version 3.6.0---指定版本下载）
[root@k8s-master01 ~]# mkdir /helm_images && cd /helm_images
[root@k8s-master01 helm_images]# helm pull ingress-nginx/ingress-nginx

# 3、更改对应的配置
[root@k8s-master01 helm_images]# tar -zxvf ingress-nginx-3.17.0.tgz && cd ingress-nginx
```

  4、新建一个名为 values-prod.yaml 的 Values 文件，用来覆盖 ingress-nginx 默认的 Values 值

```yaml
# values-prod.yaml
controller:
  name: controller
  image:
    repository: cnych/ingress-nginx
    tag: "v0.41.2"
    digest: 

  dnsPolicy: ClusterFirstWithHostNet

  hostNetwork: true

  publishService:  # hostNetwork 模式下设置为false，通过节点IP地址上报ingress status数据
    enabled: false

  kind: DaemonSet

  tolerations:   # kubeadm 安装的集群默认情况下master是有污点，需要容忍这个污点才可以部署
  - key: "node-role.kubernetes.io/master"
    operator: "Equal"
    effect: "NoSchedule"

  nodeSelector:   # 固定到node04节点
    kubernetes.io/hostname: "node04"

  service:  # HostNetwork 模式不需要创建service
    enabled: false

defaultBackend:
  enabled: true
  name: defaultbackend
  image:
    repository: cnych/ingress-nginx-defaultbackend
    tag: "1.5"
```

5、部署

```yaml
# create ns
[root@master01 Ingress]# kubectl create ns ingress-nginx
namespace/ingress-nginx created

# 部署
[root@master01 helm_images]# ll
total 0
drwxr-xr-x 4 root root 164 Jul 25 23:20 ingress-nginx
[root@master01 helm_images]# helm install --namespace ingress-nginx ingress-nginx ./ingress-nginx -f ./ingress-nginx/values-prod.yaml 
NAME: ingress-nginx
LAST DEPLOYED: Mon Jul 25 23:20:33 2022
NAMESPACE: ingress-nginx
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The ingress-nginx controller has been installed.
It may take a few minutes for the LoadBalancer IP to be available.
You can watch the status by running 'kubectl --namespace ingress-nginx get services -o wide -w ingress-nginx-controller'

An example Ingress that makes use of the controller:

  apiVersion: networking.k8s.io/v1beta1
  kind: Ingress
  metadata:
    annotations:
      kubernetes.io/ingress.class: nginx
    name: example
    namespace: foo
  spec:
    rules:
      - host: www.example.com
        http:
          paths:
            - backend:
                serviceName: exampleService
                servicePort: 80
              path: /
    # This section is only required if TLS is to be enabled for the Ingress
    tls:
        - hosts:
            - www.example.com
          secretName: example-tls

If TLS is enabled for the Ingress, a Secret containing the certificate and key must also be provided:

  apiVersion: v1
  kind: Secret
  metadata:
    name: example-tls
    namespace: foo
  data:
    tls.crt: <base64 encoded cert>
    tls.key: <base64 encoded key>
  type: kubernetes.io/tls
```

6、部署完成后查看 Pod 的运行状态

- 出现以下信息说明部署成功

```sh
[root@master01 helm_images]# kubectl get svc -n ingress-nginx
NAME                                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
ingress-nginx-controller-admission   ClusterIP   10.103.233.14    <none>        443/TCP   59s
ingress-nginx-defaultbackend         ClusterIP   10.104.233.128   <none>        80/TCP    59s
[root@master01 helm_images]# kubectl get pods -n ingress-nginx
NAME                                            READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-xs65w                  1/1     Running   0          64s
ingress-nginx-defaultbackend-796bdb7766-2lh8b   1/1     Running   0          64s
[root@master01 helm_images]# POD_NAME=$(kubectl get pods -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx -o jsonpath='{.items[0].metadata.name}')
[root@master01 helm_images]# kubectl exec -it $POD_NAME -n ingress-nginx -- /nginx-ingress-controller --version
-------------------------------------------------------------------------------
NGINX Ingress controller
  Release:       v0.41.2
  Build:         d8a93551e6e5798fc4af3eb910cef62ecddc8938
  Repository:    https://github.com/kubernetes/ingress-nginx
  nginx version: nginx/1.19.4

-------------------------------------------------------------------------------
```


# K8s 全栈服务端考核 Demo

这是一个按考核 PPT 实现的最小全栈项目：一个前端页面、一个 Node.js API、一个 MySQL 数据库，以及 Docker/Kubernetes/Jenkins 部署配置。

## 1. 功能

- 浏览器查看 `items` 列表。
- 新增一条记录。
- 后端通过 MySQL 保存数据。
- 前端通过 `/api` 调用后端，不直接连接数据库。
- MySQL 使用 PVC 持久化；线上 PVC 绑定 Master 提供的 NFS。

API：

```text
GET  /api/items
POST /api/items    body: { "name": "示例" }
GET  /healthz
```

## 2. 目录

```text
frontend/          前端页面、Nginx 配置和前端 Dockerfile
backend/           Node.js API、MySQL 驱动和后端 Dockerfile
k8s/               Namespace、MySQL、Jenkins、PVC、Service、Ingress 配置
jenkins/            Jenkins 控制器镜像构建文件
Jenkinsfile        Jenkins 构建、推送和部署流程
DEVELOPMENT_GUIDE.md  从零实施、交付和验收文档
```

## 3. 本地运行

前提：安装并启动 Docker Desktop，确认 Docker Engine 正在运行。

在仓库根目录执行：

```bash
docker compose up --build
```

浏览器打开：

```text
http://localhost:8080
```

停止本地服务：

```bash
docker compose down
```

删除本地 MySQL 数据并重新开始：

```bash
docker compose down -v
```

本地 Compose 使用固定的演示密码，只用于本机开发，不要复制到线上环境。

## 4. 本地验证

页面中新增一条数据并刷新页面，确认数据仍可查询。也可以使用：

```bash
curl http://localhost:3000/healthz
curl http://localhost:3000/api/items
curl -X POST http://localhost:3000/api/items \
  -H 'Content-Type: application/json' \
  -d '{"name":"本地验证"}'
```

检查后端 JavaScript 语法：

```bash
npm --prefix backend install
npm --prefix backend run check
```

## 5. Docker 镜像

登录 Docker Hub 后创建两个公开仓库：

```text
你的用户名/k8s-demo-frontend
你的用户名/k8s-demo-backend
```

本地构建示例：

```bash
docker build -t 你的用户名/k8s-demo-frontend:latest frontend
docker build -t 你的用户名/k8s-demo-backend:latest backend
```

Kubernetes 只能运行镜像，因此发布顺序是：

```text
代码 → Jenkins 构建镜像 → Docker Hub → Kubernetes 下载镜像
```

## 6. 线上 Kubernetes 前提

严格考核环境需要：

```text
1 台 master + 2 台 node
Ubuntu 24.x
同一地域、同一个 VPC 和子网
kubeadm、containerd、kubelet、kubectl
Calico
NGINX Ingress Controller
Headlamp
```

Master 需要提供 NFS 目录：

```text
/srv/nfs/mysql
```

部署前编辑 [`k8s/mysql-pv-pvc.yaml`](k8s/mysql-pv-pvc.yaml)，将：

```text
REPLACE_WITH_MASTER_PRIVATE_IP
```

替换为 Master 内网 IP。

服务器租赁时机：**本地 Compose 能够新增和查询数据、两个镜像能够构建后，再租三台服务器；建议在正式验收前 1～3 天租。**

## 7. 手动部署 Kubernetes

先创建 Namespace 和线上 Secret。不要把真实密码提交到 GitHub：

```bash
kubectl apply -f k8s/namespace.yaml
kubectl -n app create secret generic mysql-secret \
  --from-literal=MYSQL_ROOT_PASSWORD='替换为真实密码' \
  --from-literal=MYSQL_DATABASE='appdb' \
  --from-literal=MYSQL_USER='app' \
  --from-literal=MYSQL_PASSWORD='替换为真实密码' \
  --dry-run=client -o yaml | kubectl apply -f -
```

然后部署：

```bash
kubectl apply -f k8s/mysql-pv-pvc.yaml
kubectl apply -f k8s/mysql.yaml
kubectl apply -f k8s/backend.yaml
kubectl apply -f k8s/frontend.yaml
kubectl apply -f k8s/ingress.yaml
```

首次部署前，把 `k8s/backend.yaml` 和 `k8s/frontend.yaml` 中的 `DOCKERHUB_USER` 替换成实际 Docker Hub 用户名。也可以先应用 YAML，再使用：

```bash
kubectl -n app set image deployment/backend backend=你的用户名/k8s-demo-backend:latest
kubectl -n app set image deployment/frontend frontend=你的用户名/k8s-demo-frontend:latest
```

检查状态：

```bash
kubectl get nodes -o wide
kubectl get pods -n app
kubectl get svc -n app
kubectl get ingress -n app
kubectl get pvc -n app
```

## 8. Jenkins

先在 Master 上准备 NFS 目录：

```text
/srv/nfs/jenkins
```

部署前编辑 [`k8s/jenkins-pv-pvc.yaml`](k8s/jenkins-pv-pvc.yaml) 和 [`k8s/jenkins.yaml`](k8s/jenkins.yaml)，替换：

```text
REPLACE_WITH_MASTER_PRIVATE_IP
DOCKERHUB_USER
```

先构建并推送 Jenkins 控制器镜像：

```bash
docker build -t 你的用户名/k8s-demo-jenkins:latest jenkins
docker push 你的用户名/k8s-demo-jenkins:latest
```

然后部署 Jenkins：

```bash
kubectl apply -f k8s/jenkins.yaml
kubectl apply -f k8s/jenkins-pv-pvc.yaml
```

Jenkins 会通过 NodePort `30080` 提供访问。初始密码获取方式：

```bash
kubectl exec -n jenkins deploy/jenkins -- \
  cat /var/jenkins_home/secrets/initialAdminPassword
```

Jenkins 使用 PVC 保存 `/var/jenkins_home`。Jenkins 执行节点必须具备：

- Docker CLI 和构建镜像能力。
- `kubectl`。
- 访问目标 Kubernetes 集群的凭据。

在 Jenkins Credentials 中创建：

```text
dockerhub-creds       Username with password，密码填写 Docker Hub Access Token
mysql-root-password   Secret text
mysql-app-password    Secret text
kubeconfig             Secret file，目标 Kubernetes 集群的 kubeconfig
```

修改 `Jenkinsfile` 中的：

```text
DOCKERHUB_NAMESPACE = 'REPLACE_WITH_YOUR_DOCKERHUB_USERNAME'
```

然后创建 Pipeline 任务，选择“Pipeline script from SCM”，SCM 选择 Git，仓库填写 GitHub 地址，脚本路径填写 `Jenkinsfile`。第一次可以点击 `Build Now` 手动触发；Webhook 不是第一次成功部署的前置条件。

Jenkinsfile 会执行：

```text
Checkout → Build Images → Push Images → Deploy → Wait For Rollout
```

## 9. 验收演示

1. 浏览器打开站点公网 IP 或域名。
2. 新增一条数据。
3. 刷新页面并确认数据仍存在。
4. 删除或重启 backend Pod，确认应用恢复。
5. 删除或重启 MySQL Pod，确认数据仍存在。
6. 展示 Jenkins 成功构建记录。
7. 展示 Ingress、Service、Pod、Secret 和 PVC。
8. 展示：

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -n app
kubectl get pvc -A
```

展示 Secret 时只展示资源存在和引用关系，不展示密码内容。

## 10. 安全和清理

- 不提交 SSH 私钥、GitHub Token、Docker Hub Token、数据库真实密码。
- Docker Hub 推送使用 Access Token，不使用主账号密码。
- SSH、Jenkins 和 Kubernetes 管理端口只允许自己的 IP 或内网访问。
- 演示结束后释放三台按量计费服务器，并检查云硬盘、快照和公网 IP 是否仍在计费。

更完整的实施顺序和交付清单见 [`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md)。

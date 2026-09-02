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

登录 Docker Hub 后创建三个公开仓库：

```text
staystar/fullstack-frontend
staystar/fullstack-backend
staystar/fullstack-jenkins
```

本地构建示例：

```bash
docker build -t staystar/fullstack-frontend:latest frontend
docker build -t staystar/fullstack-backend:latest backend
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

应用 YAML 前，确认镜像地址使用 `staystar/fullstack-backend` 和 `staystar/fullstack-frontend`。也可以先应用 YAML，再使用：

```bash
kubectl -n app set image deployment/backend backend=staystar/fullstack-backend:latest
kubectl -n app set image deployment/frontend frontend=staystar/fullstack-frontend:latest
```

检查状态：

```bash
kubectl get nodes -o wide
kubectl get pods -n app
kubectl get svc -n app
kubectl get ingress -n app
kubectl get pvc -n app
```

## 8. Jenkins 自动初始化

不需要在 Jenkins 网页中手动安装插件、复制初始密码、创建 Credentials、上传 kubeconfig 或创建 Pipeline。`./scripts/deploy.sh` 会构建并推送 Jenkins 镜像，随后自动创建以下资源：

- Jenkins 管理员，账号和密码取自 `deployment/secrets.env`。
- `dockerhub-creds`、`mysql-root-password` 和 `mysql-app-password` 凭据。
- 名为 `fullstack-pipeline` 的 Pipeline，代码仓库和任务名均可在 `deployment/secrets.env` 修改。
- 只使用 `jenkins` ServiceAccount 的集群内 kubeconfig；它不使用或保存 master 管理员 kubeconfig。
- 首次 Pipeline 构建，并在脚本结束前确认结果为成功。

Jenkins 通过 NodePort `30081` 提供访问；`30080` 留给 NGINX Ingress 的应用入口。登录时使用 `JENKINS_ADMIN_USER` 和 `JENKINS_ADMIN_PASSWORD` 的值。Jenkins 使用 PVC 保存 `/var/jenkins_home`，在 Master 的 Docker Socket 上构建镜像，并以 Kubernetes RBAC 限定部署权限。

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

## 11. 三台 Ubuntu 一键部署

项目提供 [`scripts/deploy.sh`](scripts/deploy.sh)，用于从本机通过 SSH 自动完成三台 Ubuntu 服务器的基础配置、Kubernetes、Calico、NFS、NGINX Ingress、Headlamp、Jenkins 和业务资源部署。它会先构建并推送 Linux `amd64` Jenkins 镜像，再自动初始化 Jenkins 管理员、凭据、Pipeline 和首次构建。脚本默认使用 Calico `v3.32.1`、Ingress-NGINX `controller-v1.15.1` 和 Headlamp `v0.44.0`。

执行前请确认云平台安全组允许：三台服务器之间的 Kubernetes、Calico 和 NFS 内网流量；Master 对外开放 SSH `22`、Ingress `30080` 和 Jenkins `30081`。SSH 用户需要具备免密 `sudo` 权限。

你只需要填写两个本地文件，它们已被 Git 忽略：

```text
deployment/hosts.env    三台服务器的公网/内网 IP 与 SSH 私钥路径；每个值都有中文说明和示例
deployment/secrets.env  MySQL、Docker Hub、Jenkins 和 GitHub 的配置；每个值都有中文说明和示例
```

填写后运行：

```bash
cd /Users/weibin/Desktop/k8s_fullstack_assessment
./scripts/deploy.sh --dry-run
./scripts/deploy.sh
```

`--dry-run` 只检查本地配置，不会连接、构建镜像或修改服务器。正式执行会等待 Jenkins 首次构建成功；失败时脚本会明确退出并给出 Jenkins 任务地址。脚本默认使用 Kubernetes `v1.36`，如果软件源没有该小版本，可以设置 `K8S_MINOR` 为实际可用的同一版本系列。脚本不会自动执行 `kubeadm reset`，已存在的集群步骤会跳过。

`hosts.env` 和 `secrets.env` 权限为 `600`，并已被 `.gitignore` 排除。不要把这两个文件、Docker Hub Token 或 SSH 私钥提交到 GitHub。Jenkins 当前通过 Master 上的 Docker Socket 构建镜像，因此 Master 会自动安装 Docker Engine。

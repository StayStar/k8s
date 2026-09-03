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
k8s/               Namespace、StorageClass、MySQL、Jenkins、PVC、Service、Ingress 配置
jenkins/            Jenkins 控制器镜像构建文件
deployment/         一次性服务器部署、备份和验收辅助工具；应用运行不依赖它
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
/srv/nfs/jenkins
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
kubectl apply -f k8s/storage-class.yaml -f k8s/namespace.yaml
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

不需要在 Jenkins 网页中手动安装插件、复制初始密码、创建 Credentials、上传 kubeconfig 或创建 Pipeline。一次性部署工具 `./deployment/deploy.sh` 会构建并推送 Jenkins 镜像，随后自动创建以下资源：

- Jenkins 管理员，账号和密码取自 `deployment/secrets.env`。
- `dockerhub-creds`、`mysql-root-password` 和 `mysql-app-password` 凭据。
- 名为 `fullstack-pipeline` 的 Pipeline，固定读取当前 GitHub 仓库的 `main` 分支。
- 可选的 `assessment-shared-library` 全局共享库；仅题目提供库地址时，在执行命令前临时设置 `JENKINS_SHARED_LIBRARY_URL`。
- 只使用 `jenkins` ServiceAccount 的集群内 kubeconfig；它不使用或保存 master 管理员 kubeconfig。
- 首次 Pipeline 构建，并在脚本结束前确认结果为成功。

Jenkins 通过 NodePort `30081` 提供访问；`30080` 留给 NGINX Ingress 的应用入口。登录时使用 `JENKINS_ADMIN_USER` 和 `JENKINS_ADMIN_PASSWORD` 的值。Jenkins 使用 PVC 保存 `/var/jenkins_home`，在 Master 的 Docker Socket 上构建镜像，并以 Kubernetes RBAC 限定部署权限。

Jenkinsfile 会执行：

```text
Checkout → Build Images → Push Images → Deploy → Wait For Rollout
```

## 9. 验收演示

先运行：

```bash
./deployment/verify-acceptance.sh --check
```

该检查不写数据、不重启 Pod，会验证三节点、Calico、CoreDNS、Ingress、Headlamp、NFS PVC、Secret、应用入口和 Jenkins 最近一次成功构建，并把不含密码的证据写入 `deployment/evidence/acceptance-<时间>/`。

随后按顺序演示：

1. 浏览器打开站点公网 IP 或域名。
2. 新增一条数据并刷新页面。
3. 展示 Jenkins 成功构建记录和 Pipeline 阶段。
4. 展示 Ingress、Service、Pod、Secret、PV/PVC、StorageClass 和 Headlamp 页面。
5. 展示 `deployment/evidence/<部署时间>/` 与本次 `deployment/evidence/acceptance-<时间>/` 中的证据。
6. 需要实际演示恢复时运行 `./deployment/verify-acceptance.sh --exercise-recovery`。它会创建一条验收测试数据，依次重建 backend、MySQL Pod，并验证数据仍可读取；命令要求明确确认后才执行。

验收脚本会保存以下常用输出：

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -n app
kubectl get pvc -A
```

展示 Secret 时只展示资源存在和引用关系，不展示密码内容。

完整的现场讲解、截图顺序、Headlamp 安全访问方式和每项 PPT 对应关系见 [`deployment/acceptance-demo.md`](deployment/acceptance-demo.md)。

## 10. 安全和清理

- 不提交 SSH 私钥、GitHub Token、Docker Hub Token、数据库真实密码。
- Docker Hub 推送使用 Access Token，不使用主账号密码。
- SSH、Jenkins 和 Kubernetes 管理端口只允许自己的 IP 或内网访问。
- 演示结束后释放三台按量计费服务器，并检查云硬盘、快照和公网 IP 是否仍在计费。

更完整的实施顺序和交付清单见 [`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md)。

## 11. 一次性服务器部署工具

[`deployment/`](deployment/README.md) 是一次性服务器部署和验收辅助工具，与前端、后端、Kubernetes 应用清单和 Jenkins Pipeline 分开。网站部署完成后不依赖这些本机脚本。它会通过 SSH 设置主机名和时区，并完成三台 Ubuntu 服务器的 Kubernetes、Calico、NFS、NGINX Ingress、Headlamp、Jenkins 和业务资源部署；随后自动初始化 Jenkins 管理员、凭据、Pipeline 和首次构建。

执行前请确认云平台安全组允许：三台服务器之间的 Kubernetes、Calico 和 NFS 内网流量；Master 对外开放 SSH `22`、Ingress `30080` 和 Jenkins `30081`。SSH 用户需要具备免密 `sudo` 权限。

你只需要填写两个本地文件，它们已被 Git 忽略：

```text
deployment/hosts.env    三台服务器的公网/内网 IP 和 SSH 私钥路径；每个值都有中文说明和示例
deployment/secrets.env  两个 MySQL 密码、Docker Hub Token、Jenkins 管理员账号和密码；每个值都有中文说明和示例
```

填写后运行：

```bash
cd /Users/weibin/Desktop/k8s_fullstack_assessment
./deployment/deploy.sh --dry-run
./deployment/deploy.sh
```

`--dry-run` 只检查两个 `.env` 中的必填值，不会连接、构建镜像或修改服务器。正式执行会验证三个节点均为 `Ready`、CoreDNS 就绪，并用临时 Pod 验证 Calico 跨 Node 连通性；随后输出 `kubectl get nodes -o wide`、`kubectl get pods -A`、`kubectl get svc -A`，等待 Jenkins 首次构建成功。构建成功后，节点系统信息、内核、磁盘、监听端口、Ingress、PVC、StorageClass 和不含 Secret 值的 Kubernetes 资源清单会保存到 Git 忽略的 `deployment/evidence/<部署时间>/`。Docker Hub 用户名、GitHub 仓库、Jenkins 任务名、SSH 用户/端口和时区都采用脚本默认值。脚本不会自动执行 `kubeadm reset`，已存在的集群步骤会跳过。

`hosts.env` 和 `secrets.env` 权限为 `600`，并已被 `.gitignore` 排除。不要把这两个文件、Docker Hub Token 或 SSH 私钥提交到 GitHub。`deployment/ports.md` 给出了安全组端口说明；Jenkins 当前通过 Master 上的 Docker Socket 构建镜像，因此 Master 会自动安装 Docker Engine。

## 12. NFS 备份和恢复

部署成功后执行：

```bash
./deployment/backup-nfs.sh --create
```

脚本会短暂停止 Jenkins，归档 `/srv/nfs/jenkins`，并通过 MySQL 的 `mysqldump --single-transaction` 生成逻辑备份；Jenkins 会恢复到备份前的副本数。备份保留在 Master 的 `/srv/nfs/backups/`，同时下载到本机 Git 忽略目录 `deployment/backups/`。使用 `./deployment/backup-nfs.sh --list` 查看 Master 上已有备份。

## 13. 修改 MySQL 密码

不能只编辑 `deployment/secrets.env` 后重新运行 `deploy.sh`。普通部署会拒绝覆盖与线上不同的 MySQL 密码，避免数据库账号与后端配置不一致。

先创建备份，再编辑对应的值，并执行：

```bash
./deployment/backup-nfs.sh --create
./deployment/rotate-mysql-password.sh --app
```

`--app` 只轮换 `MYSQL_PASSWORD`；`--root` 只轮换 `MYSQL_ROOT_PASSWORD`；`--all` 同时轮换两个密码。轮换 root 密码时会提示输入当前 root 密码，完成后会更新 Kubernetes Secret、Jenkins 凭据并重启相关服务。

恢复属于破坏性操作：先验证 `SHA256SUMS`，再在维护窗口恢复。MySQL 可将 `mysql.sql.gz` 流式导入运行中的 `mysql` Deployment；恢复 Jenkins 时需先缩容 Jenkins、还原 `/srv/nfs/jenkins`、再恢复副本数。恢复前应先为当前数据创建一份新备份。

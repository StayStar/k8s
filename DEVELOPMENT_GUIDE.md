# K8s 全栈服务端考核开发与交付文档

## 1. 文档目的

本文档把题目 PPT 转换成一套可以从零执行到最终验收的工作计划。目标不是开发复杂业务，而是完成并证明下面这条链路：

```text
浏览器 → Ingress → Service → Pod → 数据库 → 持久化存储
```

同时证明代码可以通过下面的发布链路进入集群：

```text
代码仓库 → Jenkins → Docker 镜像 → Kubernetes 部署
```

题目来源：[`k8s_fullstack_assessment_ppt.pptx`](./k8s_fullstack_assessment_ppt.pptx)。

## 2. 最终交付范围

这是一个项目，不是五个独立项目。项目包含：

```text
一个 Kubernetes 集群
一个 Jenkins 持续集成/部署服务
一个 MySQL 数据库
一个前端服务
一个后端服务
一套自动发布流程
一套部署和验收文档
```

### 2.1 采用的最低成本技术方案

| 部分 | 方案 | 说明 |
|---|---|---|
| 代码仓库 | GitHub | 按题目要求使用 GitHub |
| 前端 | 原生 HTML + JavaScript | 只做列表、表单、新增和查询 |
| 后端 | Node.js + Express | 只提供最小 API |
| 数据库 | MySQL 8 单副本 | 题目允许 MySQL/PostgreSQL 二选一 |
| 容器 | Docker 镜像 | 前端和后端分别构建镜像 |
| 集群 | kubeadm + 1 master + 2 node | 题目硬性要求 |
| 集群网络 | Calico | 题目硬性要求 |
| 对外访问 | Ingress | 统一提供网站入口 |
| 持久化 | Master 上的 NFS + PV/PVC | 题目硬性要求 |
| CI/CD | Jenkins Pipeline | Git 提交后构建、推送并部署 |
| 可视化 | Headlamp | 提供 Kubernetes 管理页面 |
| 配置文件 | Kubernetes YAML | 本项目不强制使用 Helm |

### 2.2 明确不做的内容

以下内容不是本题最低交付范围：

- 用户登录、权限系统和复杂业务
- React/Vue/NestJS 等额外框架
- 微服务拆分
- Redis、消息队列和监控告警
- 多副本数据库和生产级高可用
- HTTPS、域名和完整备份平台
- 动态 NFS Provisioner

文档中应说明：这是考核演示环境，不是生产环境。生产环境应使用托管数据库、独立存储、备份、TLS、高可用和更细粒度权限。

## 3. 项目目录和职责

最终 Git 仓库建议如下：

```text
project/
├── frontend/          浏览器页面和前端镜像构建文件
├── backend/           API 服务和后端镜像构建文件
├── k8s/               Kubernetes 部署配置
├── jenkins/            Jenkins 控制器镜像构建文件
├── Jenkinsfile        Jenkins 自动构建和部署流程
└── README.md          面向考官的使用和部署说明
```

依赖关系：

```text
frontend/ → frontend Docker 镜像 → frontend.yaml → frontend Pod
backend/  → backend Docker 镜像  → backend.yaml  → backend Pod
MySQL 配置 → mysql.yaml → mysql Pod → PVC → NFS
Jenkins 配置 → jenkins.yaml → Jenkins Pod → PVC → NFS
Jenkinsfile → 构建两个镜像 → 推送镜像仓库 → 更新 Kubernetes
Ingress → frontend Service / backend Service
backend → mysql Service → MySQL Pod
```

前端不直接连接数据库。正确关系是：

```text
浏览器 → 前端 → 后端 API → 数据库
```

## 4. 基础设施架构

### 4.1 三台服务器

| 角色 | 作用 |
|---|---|
| `master` | 管理 Kubernetes；提供 NFS；可运行 Jenkins |
| `node-01` | Kubernetes 工作节点，运行应用 Pod |
| `node-02` | Kubernetes 工作节点，运行应用 Pod |

三台机器应满足：

```text
2 vCPU / 4 GiB / 40 GiB
Ubuntu 24.x
中国香港或同一地域
同一个 VPC 和子网
内网互通
```

题目要求一个 master 和两个 node。它可以验证多节点 Kubernetes，但只有一个 master，并不等于生产级高可用集群。

### 4.2 运行链路

```text
浏览器
  ↓
Ingress
  ├── /     → frontend Service → frontend Pod
  └── /api  → backend Service  → backend Pod
                                      ↓
                              mysql Service
                                      ↓
                              MySQL Pod
                                      ↓
                                  PVC / NFS
```

### 4.3 发布链路

```text
开发者提交代码
  ↓
GitHub
  ↓
Jenkins 读取 Jenkinsfile
  ↓
构建 frontend/backend 镜像
  ↓
推送到 Docker Hub 或其他镜像仓库
  ↓
kubectl apply / 更新镜像
  ↓
Kubernetes 创建新的 Pod
```

## 5. 服务器什么时候租

### 5.1 当前阶段：先不要租三台

当前已经具备前端、后端、Docker Compose 和 Kubernetes 配置，并已完成本地 Compose 验证。此时仍不建议立即租服务器，应先完成镜像名称统一和 Jenkins 镜像推送，避免把应用问题与集群问题同时排查。

先在本地完成以下准备：

1. 前端页面可以打开。
2. 后端 API 可以启动。
3. MySQL 可以新增和查询数据。
4. 前端可以通过 `/api` 调用后端。
5. 前端和后端 Docker 镜像可以构建。
6. Git 仓库已经建立，目录结构稳定。
7. Kubernetes YAML、Jenkinsfile 和 README 已经有第一版。

### 5.2 推荐租赁时机

在本地业务链路跑通之后、开始正式部署 Kubernetes 之前，再租三台服务器。通常安排在正式验收前 1～3 天即可。

租赁顺序：

```text
本地完成前后端和镜像
  ↓
确认账号、支付、SSH 和仓库权限
  ↓
一次性租三台云服务器
  ↓
安装 Kubernetes、NFS、Jenkins、数据库
  ↓
部署应用并反复验收
  ↓
完成演示和截图
  ↓
释放所有计费资源
```

### 5.3 什么时候必须提前租

如果你没有本地 Kubernetes 环境，或者题目要求展示真实的 `kubeadm + Calico + NFS`，就不能只在本地验证这些内容。此时在进入“阶段 1：安装 Kubernetes 集群”前租赁三台服务器。

### 5.4 租赁配置检查表

```text
[ ] 3 台服务器
[ ] 2 vCPU / 4 GiB / 40 GiB
[ ] Ubuntu 24.x
[ ] 同一地域
[ ] 同一个 VPC 和子网
[ ] 三台都有内网 IP
[ ] 最好都有公网 IP，方便 SSH 和排障
[ ] 普通按量计费，不选竞价/抢占式实例
[ ] 已设置费用提醒
```

云服务器购买时应查看完整费用明细。实例、系统盘、公网 IP、公网流量和快照可能分别计费。测试完成后要释放实例，并检查独立云盘、快照和公网 IP 是否仍在计费。

## 6. 分阶段实施计划

### 阶段 0：服务器申请与初始化

题目要求：

- 申请三台服务器。
- 配置主机名、SSH、时区和基础依赖。
- 确认三台机器可以通过内网互通。
- 记录云厂商、地域、系统版本、公网 IP、内网 IP 和开放端口。

交付证据：

```text
节点清单表
初始化命令记录
系统信息、内核版本、磁盘空间
开放端口说明
集群规划说明
问题与排障记录
```

### 阶段 1：安装 Kubernetes

实施目标：


1. 安装 containerd、kubelet、kubeadm、kubectl。
2. 使用 kubeadm 初始化 master。
3. 生成 join 命令，让两个 node 加入。
4. 安装 Calico。
5. 安装 Headlamp。
6. 确认所有节点为 `Ready`，CoreDNS 正常运行。

验收命令以题目为准：

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
```

版本说明：题面指定 Kubernetes `1.36.x`。如果软件源实际只提供其他版本，记录实际版本、原因和差异，不要隐瞒版本变化。

### 阶段 2：NFS 和 Jenkins

实施目标：

```text
master:/srv/nfs/jenkins
        ↓
Jenkins PV → Jenkins PVC → Jenkins Pod
```

Jenkins 必须具备：

- Namespace、Deployment、Service、PVC。
- 管理员密码获取方式。
- Pod 重启后任务和配置仍存在。
- 构建 Docker 镜像和执行 Kubernetes 部署的权限。
- Pipeline Library 参数预留位置。

Jenkins 初始密码只在服务器或 Jenkins 凭据中使用，不提交到代码仓库。

Pipeline Library 的 URL 由出题人后续提供。在 URL 未提供前，文档只预留配置项，不虚构地址。

### 阶段 3：MySQL、Secret 和 PVC

选择 MySQL 8，部署单副本即可。

部署关系：

```text
数据库密码 → Kubernetes Secret
数据库文件 → MySQL PVC → NFS
后端访问   → mysql Service
```

必须满足：

- 数据库使用 PVC。
- 数据库密码通过 Secret 注入。
- 后端使用 Service 名称访问数据库。
- 数据库 Pod 删除或重启后，原数据仍可读取。

生产环境说明：本题为了降低复杂度允许单副本数据库；生产环境应考虑托管数据库、备份、恢复、高可用和独立存储。

### 阶段 4：前后端分离站点

最小业务功能：

```text
前端：展示列表、输入框、新增按钮
后端：新增数据、查询数据
数据库：保存 items 表
```

建议 API：

```text
GET  /api/items    查询列表
POST /api/items    新增一条数据
```

前端使用同域名路径 `/api/items`，由 Ingress 将 API 请求转发给后端，避免额外的跨域配置。

### 阶段 5：CI/CD

Jenkins Pipeline 至少包含：

```text
Checkout
  ↓
Build Backend Image
  ↓
Build Frontend Image
  ↓
Push Images
  ↓
Deploy Kubernetes YAML
  ↓
Wait For Rollout
```

最初可以在 Jenkins 页面手动触发构建。Git Webhook 可以作为补充，不应成为第一次成功部署的前置条件。

## 7. 资源之间的依赖和启动顺序

### 7.1 基础设施顺序

```text
云服务器
  ↓
VPC、内网、安全组
  ↓
containerd 和 Kubernetes
  ↓
Calico
  ↓
NFS
  ↓
PV/PVC
  ↓
Secret
  ↓
MySQL
  ↓
Backend
  ↓
Frontend
  ↓
Ingress
  ↓
Jenkins 自动发布
```

Jenkins 也可以较早部署，但它必须在 Kubernetes 集群和持久化存储可用后配置，正式发布时还需要镜像仓库凭据和 Kubernetes 权限。

### 7.2 用户访问顺序

```text
1. 用户打开公网 IP 或域名。
2. 请求先到 Ingress。
3. Ingress 将页面请求转给 frontend Service。
4. 前端页面请求 /api/items。
5. Ingress 将 /api 请求转给 backend Service。
6. backend Pod 通过 mysql Service 访问数据库。
7. MySQL 将数据保存到 PVC/NFS。
```

### 7.3 代码发布顺序

```text
1. 修改 frontend 或 backend。
2. 提交到 GitHub。
3. Jenkins 拉取代码。
4. Jenkins 构建新的 Docker 镜像。
5. Jenkins 推送镜像仓库。
6. Jenkins 更新 Kubernetes Deployment。
7. Kubernetes 启动新 Pod。
8. Ingress 和 Service 继续提供访问。
```

## 8. 最终验收演示脚本

按照用户视角、工程实现、持久化和安全的顺序演示：

1. 浏览器打开站点公网 IP 或域名，证明 Ingress 生效。
2. 新增一条数据，证明前端调用后端并写入数据库。
3. 刷新或重新查询，证明读取路径正常。
4. 删除或重启 backend Pod，证明应用可以恢复。
5. 删除或重启 MySQL Pod，确认数据仍然存在。
6. 展示 Jenkins 成功构建记录。
7. 展示 Git 提交、镜像构建、部署结果。
8. 展示 Ingress、Service、Pod、Secret 和 PVC。
9. 展示 `kubectl` 验收输出和 Headlamp 页面。

建议准备的命令输出：

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -n app
kubectl get pvc -A
kubectl get secret -n app
kubectl rollout status deployment/backend -n app
```

展示 Secret 时只能展示 Secret 存在及其引用关系，不要公开密码内容。

## 9. 交付清单

### 9.1 代码和配置

```text
[ ] GitHub 仓库地址
[ ] frontend/ 目录
[ ] backend/ 目录
[ ] frontend/Dockerfile
[ ] backend/Dockerfile
[ ] k8s/ YAML 配置
[ ] jenkins/Dockerfile
[ ] Jenkins PV/PVC 和 Deployment YAML
[ ] Jenkinsfile
[ ] README.md
```

### 9.2 平台和环境

```text
[ ] 云厂商和地域
[ ] 三台服务器角色、公网 IP、内网 IP
[ ] Ubuntu 版本
[ ] Kubernetes 版本
[ ] containerd、Calico、Ingress、Headlamp 版本
[ ] 开放端口和安全组说明
[ ] 集群规划说明
```

### 9.3 Jenkins 和部署证据

```text
[ ] Jenkins 首页可访问截图
[ ] Jenkins Pipeline 配置
[ ] 成功构建记录截图
[ ] 镜像仓库中的镜像标签
[ ] Kubernetes 部署成功截图
[ ] Git 提交到部署的过程说明
```

### 9.4 验收证据

```text
[ ] 浏览器访问截图
[ ] 新增数据截图
[ ] 查询数据截图
[ ] backend Pod 重启后恢复截图
[ ] MySQL Pod 重启后数据仍然存在截图
[ ] kubectl get nodes -o wide
[ ] kubectl get pods -A
[ ] kubectl get svc -A
[ ] Ingress、Secret、PVC 截图
```

### 9.5 文档内容

README 或提交文档必须包含：

```text
环境信息与版本
部署前提
关键命令和配置说明
代码目录说明
访问地址和必要账号信息
遇到的问题与解决过程
最终验收结果
生产环境改进说明
```

账号信息只能放临时测试账号或说明获取方法，不能把真实密码提交到公开仓库。

## 10. 三天时间安排

### 第 0 天：本地准备，不租服务器

```text
完成最小前端和后端
完成 MySQL 本地读写
完成 Docker 镜像构建
创建 Git 仓库
准备 k8s/ 和 Jenkinsfile 初稿
```

### 第 1 天：正式租赁服务器并完成集群

```text
上午：创建三台云服务器、初始化和互通检查
下午：kubeadm、Calico、Headlamp
晚上：节点、Pod、Service 验收
```

### 第 2 天：存储、Jenkins、数据库

```text
上午：NFS、PV、PVC
下午：Jenkins 部署和持久化
晚上：MySQL、Secret、数据重启验证
```

### 第 3 天：应用、CI/CD 和材料

```text
上午：前端、后端和 Ingress 部署
下午：Jenkins 构建、推送、部署
晚上：完整演示、截图、README、排障记录
```

## 11. 风险和处理策略

| 风险 | 处理方式 |
|---|---|
| Kubernetes 题面版本不可用 | 记录实际版本和原因，不隐瞒差异 |
| 香港镜像下载慢 | 提前测试网络，必要时记录失败原因并重试 |
| 2C4G 资源紧张 | 保持单副本，先部署核心链路，减少无关服务 |
| Jenkins 配置复杂 | 先手动构建成功，再补 Webhook |
| 数据库 Pod 重启丢数据 | 检查 PVC 是否绑定、挂载路径是否正确 |
| 前端跨域 | 使用同域名 `/api`，通过 Ingress 分流 |
| 云费用持续增加 | 按量计费、设置提醒，结束后释放实例和附属资源 |
| Secret 泄露 | 密码只放 Kubernetes Secret/Jenkins Credentials，不提交仓库 |

## 12. 完成标准

只有同时满足以下条件，才算本项目完成：

```text
[ ] 三台节点加入 Kubernetes 集群并 Ready
[ ] Calico 和 CoreDNS 正常
[ ] Headlamp 可访问
[ ] Jenkins 首页可访问且数据持久化
[ ] MySQL 使用 Secret 和 PVC
[ ] 前端页面可以访问
[ ] 后端 API 可以新增和查询数据
[ ] Ingress → Service → Pod → DB 链路可解释、可演示
[ ] backend Pod 重启后恢复
[ ] MySQL Pod 重启后数据不丢失
[ ] Jenkins 能完成构建、推送和部署
[ ] Git 仓库、YAML、Jenkinsfile、截图和 README 齐全
[ ] 所有敏感凭据未提交到公开仓库
```

## 13. 当前下一步

当前仓库已经包含业务代码、Dockerfile、Jenkinsfile 和 Kubernetes 配置，且 GitHub 与 Docker Hub 应用仓库已经准备好。建议执行顺序是：

```text
1. 创建 staystar/fullstack-jenkins 镜像仓库。
2. 本地确认 frontend、backend 和 Jenkins 镜像都能构建。
3. 租三台香港云服务器并完成 Kubernetes、NFS、Jenkins 和数据库部署。
4. 在 Jenkins 中配置 Docker Hub、Kubeconfig 和数据库凭据。
5. 触发 Pipeline，完成镜像推送、应用部署和滚动更新。
6. 按验收脚本截图并整理提交材料。
```

服务器租赁的明确结论：**现在不必租；等本地前后端和镜像可以运行后，在正式开始 Kubernetes 部署前租三台。**

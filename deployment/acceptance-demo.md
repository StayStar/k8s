# PPT 验收演示

先执行只读检查：

```bash
./deployment/verify-acceptance.sh --check
```

该命令不写入数据、不重启 Pod。它会验证三节点 Ready、Calico、CoreDNS、Ingress NGINX、Headlamp、NFS StorageClass/PV/PVC、MySQL Secret、Jenkins Secret、业务服务、Jenkins 最近一次 Pipeline 成功，以及公网 `Ingress` API 可访问。所有不含密码的结果保存在 `deployment/evidence/acceptance-<时间>/`。

浏览器演示按下面顺序进行：

1. 打开脚本输出的应用地址 `http://Master公网IP:30080`，展示页面通过 Ingress 访问。
2. 在页面新增一条数据并刷新，展示前端、后端 API 和 MySQL 的读写链路。
3. 在 Jenkins 页面 `http://Master公网IP:30081` 展示 `fullstack-pipeline` 最近一次成功构建；展示其 `Checkout -> Build Images -> Push Images -> Deploy -> Wait For Rollout` 阶段。
4. 打开 GitHub 仓库最新提交和 Docker Hub 中 `staystar/fullstack-frontend`、`staystar/fullstack-backend` 的镜像标签，说明它们对应本次 Jenkins 构建。
5. 打开本次 `deployment/evidence/acceptance-<时间>/`，展示 `kubectl-nodes.txt`、`kubectl-pods.txt`、`kubectl-services.txt`、`kubectl-ingress.txt`、`kubectl-pvcs.txt`、`kubectl-storageclasses.txt` 和 `manifests/`。
6. 只展示 `kubectl` 中 Secret 资源存在及工作负载的 `secretKeyRef`/`envFrom` 引用；不要执行 `kubectl get secret -o yaml` 或解码 Secret。

需要演示 Pod 恢复和数据库持久化时，再执行：

```bash
./deployment/verify-acceptance.sh --exercise-recovery
```

这个命令会先完成只读检查，再写入一条名为 `acceptance-<时间>` 的测试记录，依次删除 `backend` 和 `mysql` Pod，等待 Kubernetes 重建后确认这条记录仍可读取。它会要求输入 `DELETE_PODS`；只有无人值守演示时才附加 `--yes`。执行前建议先运行 `./deployment/backup-nfs.sh --create`。

Headlamp 不需要暴露到公网。打开一个单独终端并保持运行：

```bash
ssh -i '/Mac上的私钥路径.pem' -L 4466:127.0.0.1:4466 ubuntu@Master公网IP \
  'sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-system port-forward service/headlamp 4466:80'
```

然后在 Mac 浏览器打开 `http://127.0.0.1:4466`。需要时使用 Kubernetes ServiceAccount Token 登录；展示完成后按 `Ctrl+C` 关闭该 SSH 通道。

PPT 对应关系：

| PPT 验收点 | 演示证据 |
|---|---|
| 三台服务器、SSH、端口、初始化 | `deployment/evidence/<部署时间>/` 与 `ports.md` |
| Kubernetes 1 master + 2 node、Calico、CoreDNS、Headlamp | `kubectl-nodes.txt`、`kubectl-pods.txt`、Headlamp 页面 |
| Jenkins + NFS PVC + Pipeline Library 预留 | Jenkins 页面、`jenkins-pvc`、`jenkins-pv`、`k8s/jenkins.yaml` |
| MySQL + Secret + PVC | `mysql-pvc`、`mysql-pv`、`mysql-secret` 元数据与 `k8s/mysql.yaml` |
| GitHub -> Jenkins -> 镜像 -> Kubernetes | Git 仓库、Jenkins 成功构建、`Jenkinsfile`、`manifests/` |
| 浏览器 -> Ingress -> Service -> Pod -> DB | 页面新增/刷新、`app-items-*.json`、Ingress/Service/Pod 证据 |
| Pod 重建后服务恢复与数据持久化 | `--exercise-recovery` 产生的 `*-pod-delete.txt`、`*-pod-ready.txt`、`app-items-after-*-recovery.json` |

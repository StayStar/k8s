# 部署工具

本目录是一次性服务器部署和验收辅助工具，不是前端、后端、Kubernetes 应用或 Jenkins Pipeline 的运行依赖。项目部署完成后，网站和 Jenkins 不需要持续运行这些本机脚本。

只需填写两个 Git 忽略文件：

| 文件 | 必填值 |
|---|---|
| `hosts.env` | Master、Node 01、Node 02 的 SSH 地址和内网 IP，以及 Mac 上的 SSH 私钥路径 |
| `secrets.env` | 两个 MySQL 密码、Docker Hub Read & Write Token、Jenkins 管理员账号和密码 |

脚本内固定默认值：Docker Hub 用户名 `staystar`、GitHub 仓库地址、Jenkins 任务名、SSH 用户 `ubuntu`、SSH 端口 `22`、时区 `Asia/Shanghai`。题目后续提供 Shared Library 地址时，可以在单次命令前临时设置 `JENKINS_SHARED_LIBRARY_URL` 和 `JENKINS_SHARED_LIBRARY_VERSION`，无需写入 `.env`。

从项目根目录执行：

```bash
./deployment/deploy.sh --dry-run
./deployment/deploy.sh
```

部署完成后，普通部署命令不允许通过修改 `secrets.env` 覆盖线上 MySQL 密码。这样可避免只更新应用配置、却没有更新数据库账号而导致服务不可用。

需要修改密码时，先创建备份，再编辑 `secrets.env`，然后选择对应命令：

```bash
./deployment/backup-nfs.sh --create
./deployment/rotate-mysql-password.sh --app
./deployment/rotate-mysql-password.sh --root
./deployment/rotate-mysql-password.sh --all
```

`--app` 只修改 `MYSQL_PASSWORD`，`MYSQL_ROOT_PASSWORD` 必须保持当前值。`--root` 只修改 `MYSQL_ROOT_PASSWORD`，`--all` 同时修改两个密码；后二者都会安全提示输入当前 root 密码。轮换时 MySQL、后端和 Jenkins 会短暂重启以读取新的 Secret，密码不会输出到终端或写入 Git。

验收使用：

```bash
./deployment/verify-acceptance.sh --check
./deployment/verify-acceptance.sh --exercise-recovery
```

第一条只读检查不会写数据或重启 Pod；第二条会新增一个验收测试记录，并依次重建 backend、MySQL Pod 来证明恢复与持久化。详细演示顺序和 Headlamp 访问方法见 [acceptance-demo.md](acceptance-demo.md)。

`evidence/` 保存验收文本，`backups/` 保存本机下载的备份；两者均被 Git 忽略。安全组规则见 [ports.md](ports.md)。

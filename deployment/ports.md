# 云安全组与端口说明

考核环境优先保证集群内部连通：三台服务器在同一 VPC/子网时，安全组应允许三台内网 IP 之间的全部 TCP、UDP 和 ICMP 流量。这样 Kubernetes、Calico、NFS 和节点健康检查不会被额外端口规则拦截。

对公网只开放下面的最小端口：

| 目标 | 协议/端口 | 来源 | 用途 |
|---|---|---|---|
| 三台服务器 | TCP `22` | 本人当前公网 IP | Mac 通过 SSH 执行部署和排障 |
| Master | TCP `30080` | 演示访问者或本人公网 IP | NGINX Ingress 的前后端网站入口 |
| Master | TCP `30081` | 本人当前公网 IP | Jenkins 管理页面 |
| Master | TCP `6443` | 三台服务器内网 IP；仅在需要从 Mac 管理时增加本人公网 IP | Kubernetes API Server |

不要对公网开放 MySQL `3306`、kubelet `10250`、etcd `2379-2380`、控制面 `10257/10259`、NFS `2049` 或 Calico 相关端口。部署后，`deployment/deploy.sh` 会把各节点的监听端口采集到 Git 忽略的 `deployment/evidence/`，作为交付材料的一部分。

#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SSH_USER="${SSH_USER-ecs-user}"
SSH_PORT="${SSH_PORT-22}"
SSH_KEY="${SSH_KEY-}"
TIMEZONE="${TIMEZONE-Asia/Shanghai}"
MASTER_HOST="${MASTER_HOST-}"
MASTER_PRIVATE_IP="${MASTER_PRIVATE_IP-}"
NODE01_HOST="${NODE01_HOST-}"
NODE01_PRIVATE_IP="${NODE01_PRIVATE_IP-}"
NODE02_HOST="${NODE02_HOST-}"
NODE02_PRIVATE_IP="${NODE02_PRIVATE_IP-}"

K8S_MINOR="${K8S_MINOR-v1.36}"
POD_CIDR="${POD_CIDR-192.168.0.0/16}"
CALICO_VERSION="${CALICO_VERSION-v3.32.1}"
INGRESS_NGINX_VERSION="${INGRESS_NGINX_VERSION-controller-v1.15.1}"
HEADLAMP_VERSION="${HEADLAMP_VERSION-v0.44.0}"
HEADLAMP_MANIFEST_URL="${HEADLAMP_MANIFEST_URL-https://raw.githubusercontent.com/kubernetes-sigs/headlamp/$HEADLAMP_VERSION/kubernetes-headlamp.yaml}"
INSTALL_HEADLAMP="${INSTALL_HEADLAMP-1}"
MYSQL_DATABASE="${MYSQL_DATABASE-appdb}"
MYSQL_USER="${MYSQL_USER-app}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD-}"
MYSQL_PASSWORD="${MYSQL_PASSWORD-}"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME-staystar}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN-}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER-}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD-}"
GITHUB_REPOSITORY_URL="${GITHUB_REPOSITORY_URL-https://github.com/StayStar/k8s.git}"
JENKINS_JOB_NAME="${JENKINS_JOB_NAME-fullstack-pipeline}"
DRY_RUN=0
EVIDENCE_DIR=""

usage() {
  cat <<'USAGE'
Usage:
  Set the variables below, then run from the repository root.

Required for a full deployment:
  MASTER_HOST MASTER_PRIVATE_IP NODE01_HOST NODE01_PRIVATE_IP NODE02_HOST NODE02_PRIVATE_IP
  SSH_KEY MYSQL_ROOT_PASSWORD MYSQL_PASSWORD DOCKERHUB_TOKEN
  JENKINS_ADMIN_USER JENKINS_ADMIN_PASSWORD

Defaults:
  SSH_USER=ecs-user SSH_PORT=22
  TIMEZONE=Asia/Shanghai
  K8S_MINOR=v1.36 POD_CIDR=192.168.0.0/16
  CALICO_VERSION=v3.32.1 INGRESS_NGINX_VERSION=controller-v1.15.1
  HEADLAMP_VERSION=v0.44.0 INSTALL_HEADLAMP=1

Options:
  --dry-run    Validate parameters and print the plan only
  -h, --help   Show this help

Example:
  MASTER_HOST=203.0.113.10 MASTER_PRIVATE_IP=10.0.0.10 \
  NODE01_HOST=203.0.113.11 NODE01_PRIVATE_IP=10.0.0.11 \
  NODE02_HOST=203.0.113.12 NODE02_PRIVATE_IP=10.0.0.12 \
  SSH_KEY=~/.ssh/id_ed25519 ./deployment/deploy-cluster.sh
USAGE
}

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

trap 'printf "ERROR: deployment stopped at line %s\n" "$LINENO" >&2' ERR

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

validate_host() {
  local name=$1
  local value=$2
  [[ -n "$value" ]] || die "$name is required"
  [[ "$value" != *[[:space:]]* ]] || die "$name must not contain whitespace"
  [[ "$value" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "$name contains unsupported characters"
}

require_command ssh
require_command scp
require_command base64
validate_host MASTER_HOST "$MASTER_HOST"
validate_host MASTER_PRIVATE_IP "$MASTER_PRIVATE_IP"
validate_host NODE01_HOST "$NODE01_HOST"
validate_host NODE01_PRIVATE_IP "$NODE01_PRIVATE_IP"
validate_host NODE02_HOST "$NODE02_HOST"
validate_host NODE02_PRIVATE_IP "$NODE02_PRIVATE_IP"

[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || die "SSH_PORT must be numeric"
[[ "$TIMEZONE" == UTC || "$TIMEZONE" =~ ^[A-Za-z0-9_.+-]+(/[A-Za-z0-9_.+-]+)+$ ]] || die "TIMEZONE must look like Asia/Shanghai or UTC"
[[ "$K8S_MINOR" =~ ^v[0-9]+\.[0-9]+$ ]] || die "K8S_MINOR must look like v1.36"
[[ "$CALICO_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "CALICO_VERSION must look like v3.32.1"
[[ "$INGRESS_NGINX_VERSION" =~ ^controller-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "INGRESS_NGINX_VERSION must look like controller-v1.15.1"
[[ "$HEADLAMP_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "HEADLAMP_VERSION must look like v0.44.0"
[[ "$INSTALL_HEADLAMP" == 0 || "$INSTALL_HEADLAMP" == 1 ]] || die "INSTALL_HEADLAMP must be 0 or 1"
[[ "$JENKINS_JOB_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "JENKINS_JOB_NAME must contain lowercase letters, digits, and hyphens only"
[[ "$GITHUB_REPOSITORY_URL" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$ ]] || die "GITHUB_REPOSITORY_URL must look like https://github.com/owner/repository.git"

[[ -n "$SSH_KEY" ]] || die "SSH_KEY must not be empty"
[[ -f "$SSH_KEY" ]] || die "SSH_KEY does not exist: $SSH_KEY"
[[ -n "$MYSQL_ROOT_PASSWORD" ]] || die "MYSQL_ROOT_PASSWORD must not be empty"
[[ -n "$MYSQL_PASSWORD" ]] || die "MYSQL_PASSWORD must not be empty"
[[ -n "$DOCKERHUB_USERNAME" ]] || die "DOCKERHUB_USERNAME must not be empty"
[[ -n "$DOCKERHUB_TOKEN" ]] || die "DOCKERHUB_TOKEN must not be empty"
[[ -n "$JENKINS_ADMIN_USER" ]] || die "JENKINS_ADMIN_USER must not be empty"
[[ -n "$JENKINS_ADMIN_PASSWORD" ]] || die "JENKINS_ADMIN_PASSWORD must not be empty"
[[ "$DOCKERHUB_USERNAME" == staystar ]] || die "DOCKERHUB_USERNAME must be staystar for this repository's image names"

SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -p $SSH_PORT"
SCP_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -P $SSH_PORT"
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
  SCP_OPTS="$SCP_OPTS -i $SSH_KEY"
fi

ssh_command() {
  local host=$1
  shift
  ssh $SSH_OPTS "$SSH_USER@$host" "$@"
}

ssh_root_command() {
  local host=$1
  local command=$2
  ssh $SSH_OPTS "$SSH_USER@$host" "sudo -n bash -lc $(printf '%q' "$command")"
}

ssh_root_script() {
  local host=$1
  shift
  ssh $SSH_OPTS "$SSH_USER@$host" sudo -n bash -s -- "$@"
}

check_ssh() {
  log "Checking SSH access"
  ssh_command "$MASTER_HOST" true
  ssh_command "$NODE01_HOST" true
  ssh_command "$NODE02_HOST" true
}

prepare_node() {
  local host=$1
  local node_name=$2
  local install_docker=$3

  log "Preparing $node_name ($host)"
  ssh_root_script "$host" "$node_name" "$install_docker" "$K8S_MINOR" "$SSH_USER" "$TIMEZONE" <<'REMOTE'
set -Eeuo pipefail
node_name="$1"
install_docker="$2"
k8s_minor="$3"
ssh_user="$4"
timezone="$5"

if [[ "$(hostname)" != "$node_name" ]]; then
  hostnamectl set-hostname "$node_name"
fi
timedatectl set-timezone "$timezone"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg containerd nfs-common

swapoff -a
sed -ri '/[[:space:]]swap[[:space:]]/ s/^/#/' /etc/fstab

cat >/etc/modules-load.d/k8s.conf <<'MODULES'
overlay
br_netfilter
MODULES
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'SYSCTL'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
SYSCTL
sysctl --system >/dev/null

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/$k8s_minor/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
printf 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/%s/deb/ /\n' "$k8s_minor" \
  >/etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

if [[ "$install_docker" == yes ]]; then
  apt-get install -y docker.io
  systemctl enable --now docker
  usermod -aG docker "$ssh_user" || true
fi
REMOTE
}

init_master() {
  log "Initializing Kubernetes master"
  if ssh_root_command "$MASTER_HOST" 'test -f /etc/kubernetes/admin.conf'; then
    warn "Kubernetes admin.conf already exists; skipping kubeadm init"
    return
  fi

  ssh_root_script "$MASTER_HOST" "$MASTER_PRIVATE_IP" "$POD_CIDR" "$SSH_USER" <<'REMOTE'
set -Eeuo pipefail
master_ip="$1"
pod_cidr="$2"
ssh_user="$3"
kubeadm init \
  --apiserver-advertise-address="$master_ip" \
  --pod-network-cidr="$pod_cidr" \
  --cri-socket=unix:///run/containerd/containerd.sock

install -d -m 0700 /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
if [[ "$ssh_user" != root ]] && id "$ssh_user" >/dev/null 2>&1; then
  install -d -m 0700 "/home/$ssh_user/.kube"
  cp /etc/kubernetes/admin.conf "/home/$ssh_user/.kube/config"
  chown -R "$ssh_user:$ssh_user" "/home/$ssh_user/.kube"
fi
REMOTE
}

join_worker() {
  local host=$1
  local node_name=$2

  log "Joining $node_name to the cluster"
  if ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get node $node_name >/dev/null 2>&1"; then
    warn "$node_name is already registered in the cluster; skipping kubeadm join"
    return
  fi
  if ssh_root_command "$host" 'test -f /etc/kubernetes/kubelet.conf'; then
    die "$node_name has a kubelet configuration but is not registered in the cluster; inspect it before rerunning"
  fi

  local join_command
  join_command="$(ssh_root_command "$MASTER_HOST" 'kubeadm token create --print-join-command')"
  ssh_root_command "$host" "$join_command --cri-socket unix:///run/containerd/containerd.sock"
}

configure_nfs() {
  log "Configuring NFS on master"
  ssh_root_script "$MASTER_HOST" "$MASTER_PRIVATE_IP" "$NODE01_PRIVATE_IP" "$NODE02_PRIVATE_IP" <<'REMOTE'
set -Eeuo pipefail
master_ip="$1"
node01_ip="$2"
node02_ip="$3"

export DEBIAN_FRONTEND=noninteractive
apt-get install -y nfs-kernel-server
install -d -m 0777 /srv/nfs/mysql /srv/nfs/jenkins
touch /etc/exports

for path in /srv/nfs/mysql /srv/nfs/jenkins; do
  for ip in "$master_ip" "$node01_ip" "$node02_ip"; do
    line="$path $ip(rw,sync,no_subtree_check)"
    grep -Fqx "$line" /etc/exports || printf '%s\n' "$line" >>/etc/exports
  done
done

exportfs -rav
systemctl enable --now nfs-server
REMOTE
}

install_addons() {
  log "Installing Calico"
  ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/calico.yaml"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s'

  log "Installing NGINX Ingress Controller"
  ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/$INGRESS_NGINX_VERSION/deploy/static/provider/baremetal/deploy.yaml"
  ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n ingress-nginx patch service ingress-nginx-controller --type=strategic --patch '{\"spec\":{\"ports\":[{\"name\":\"http\",\"port\":80,\"nodePort\":30080}]}}'"
  ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n ingress-nginx get service ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name==\"http\")].nodePort}' | grep -qx 30080"

  if [[ "$INSTALL_HEADLAMP" == 1 ]]; then
    log "Installing Headlamp"
    ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f $HEADLAMP_MANIFEST_URL"
  fi
}

verify_cluster() {
  log "Verifying Kubernetes acceptance conditions"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl wait --for=condition=Ready node/master node/node-01 node/node-02 --timeout=300s'
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-system rollout status deployment/coredns --timeout=300s'

  log "Verifying cross-node Calico connectivity"
  ssh_root_script "$MASTER_HOST" <<'REMOTE'
set -Eeuo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

cleanup() {
  kubectl -n kube-system delete pod cni-check-node-01 cni-check-node-02 --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

cat <<'MANIFEST' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cni-check-node-01
  namespace: kube-system
  labels:
    app: cni-check
spec:
  nodeName: node-01
  restartPolicy: Never
  containers:
    - name: check
      image: busybox:1.36.1
      command: ["sh", "-c", "sleep 300"]
---
apiVersion: v1
kind: Pod
metadata:
  name: cni-check-node-02
  namespace: kube-system
  labels:
    app: cni-check
spec:
  nodeName: node-02
  restartPolicy: Never
  containers:
    - name: check
      image: busybox:1.36.1
      command: ["sh", "-c", "sleep 300"]
MANIFEST

kubectl -n kube-system wait --for=condition=Ready pod/cni-check-node-01 pod/cni-check-node-02 --timeout=300s
node02_ip="$(kubectl -n kube-system get pod cni-check-node-02 -o jsonpath='{.status.podIP}')"
[[ -n "$node02_ip" ]] || { echo 'CNI connectivity check pod has no IP address' >&2; exit 1; }
kubectl -n kube-system exec cni-check-node-01 -- ping -c 3 -W 2 "$node02_ip"
REMOTE

  log "Kubernetes acceptance output"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide'
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A'
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get svc -A'
}

copy_manifests() {
  log "Copying Kubernetes manifests to master"
  REMOTE_K8S_DIR="$(ssh_command "$MASTER_HOST" 'mktemp -d /tmp/k8s-fullstack.XXXXXX')"
  scp $SCP_OPTS \
    "$REPO_ROOT/k8s/namespace.yaml" \
    "$REPO_ROOT/k8s/storage-class.yaml" \
    "$REPO_ROOT/k8s/mysql-pv-pvc.yaml" \
    "$REPO_ROOT/k8s/mysql.yaml" \
    "$REPO_ROOT/k8s/backend.yaml" \
    "$REPO_ROOT/k8s/frontend.yaml" \
    "$REPO_ROOT/k8s/ingress.yaml" \
    "$REPO_ROOT/k8s/jenkins.yaml" \
    "$REPO_ROOT/k8s/jenkins-kubeconfig.yaml" \
    "$REPO_ROOT/k8s/jenkins-pv-pvc.yaml" \
    "$SSH_USER@$MASTER_HOST:$REMOTE_K8S_DIR/"
  ssh_root_command "$MASTER_HOST" "sed -i 's/REPLACE_WITH_MASTER_PRIVATE_IP/$MASTER_PRIVATE_IP/g' $REMOTE_K8S_DIR/jenkins-pv-pvc.yaml $REMOTE_K8S_DIR/mysql-pv-pvc.yaml"
  ssh_root_command "$MASTER_HOST" "chown -R root:root $REMOTE_K8S_DIR"
}

apply_secret() {
  log "Applying MySQL Secret"
  local root_password_encoded
  local app_password_encoded
  local database_encoded
  local user_encoded
  root_password_encoded="$(printf '%s' "$MYSQL_ROOT_PASSWORD" | base64 | tr -d '\n')"
  app_password_encoded="$(printf '%s' "$MYSQL_PASSWORD" | base64 | tr -d '\n')"
  database_encoded="$(printf '%s' "$MYSQL_DATABASE" | base64 | tr -d '\n')"
  user_encoded="$(printf '%s' "$MYSQL_USER" | base64 | tr -d '\n')"

  local current_root_password_encoded
  local current_app_password_encoded
  current_root_password_encoded="$(ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n app get secret mysql-secret -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}'" 2>/dev/null || true)"
  current_app_password_encoded="$(ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n app get secret mysql-secret -o jsonpath='{.data.MYSQL_PASSWORD}'" 2>/dev/null || true)"

  if [[ -n "$current_root_password_encoded$current_app_password_encoded" ]] \
    && [[ "$current_root_password_encoded" != "$root_password_encoded" || "$current_app_password_encoded" != "$app_password_encoded" ]]; then
    die "MySQL passwords in deployment/secrets.env differ from the running cluster. Use ./deployment/rotate-mysql-password.sh instead of a normal deployment."
  fi

  local manifest
  manifest="$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: app
type: Opaque
data:
  MYSQL_ROOT_PASSWORD: $root_password_encoded
  MYSQL_DATABASE: $database_encoded
  MYSQL_USER: $user_encoded
  MYSQL_PASSWORD: $app_password_encoded
EOF
)"
  printf '%s\n' "$manifest" \
    | ssh $SSH_OPTS "$SSH_USER@$MASTER_HOST" 'sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -' >/dev/null
}

encode_secret_value() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

jenkins_bootstrap_manifest() {
  cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-bootstrap
  namespace: jenkins
type: Opaque
data:
  JENKINS_ADMIN_USER: $(encode_secret_value "$JENKINS_ADMIN_USER")
  JENKINS_ADMIN_PASSWORD: $(encode_secret_value "$JENKINS_ADMIN_PASSWORD")
  DOCKERHUB_USERNAME: $(encode_secret_value "$DOCKERHUB_USERNAME")
  DOCKERHUB_TOKEN: $(encode_secret_value "$DOCKERHUB_TOKEN")
  MYSQL_ROOT_PASSWORD: $(encode_secret_value "$MYSQL_ROOT_PASSWORD")
  MYSQL_PASSWORD: $(encode_secret_value "$MYSQL_PASSWORD")
  GITHUB_REPOSITORY_URL: $(encode_secret_value "$GITHUB_REPOSITORY_URL")
  JENKINS_JOB_NAME: $(encode_secret_value "$JENKINS_JOB_NAME")
  JENKINS_SHARED_LIBRARY_URL: "$(encode_secret_value "${JENKINS_SHARED_LIBRARY_URL-}")"
  JENKINS_SHARED_LIBRARY_VERSION: "$(encode_secret_value "${JENKINS_SHARED_LIBRARY_VERSION-main}")"
EOF
}

apply_jenkins_bootstrap_secret() {
  log "Applying Jenkins bootstrap Secret"
  jenkins_bootstrap_manifest \
    | ssh $SSH_OPTS "$SSH_USER@$MASTER_HOST" 'sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -' >/dev/null
}

deploy_resources() {
  copy_manifests
  local docker_gid
  docker_gid="$(ssh_root_command "$MASTER_HOST" "getent group docker | cut -d: -f3")"
  [[ "$docker_gid" =~ ^[0-9]+$ ]] || die "Could not determine the host docker group ID"
  ssh_root_command "$MASTER_HOST" "sed -i 's/REPLACE_WITH_DOCKER_GID/$docker_gid/g' $REMOTE_K8S_DIR/jenkins.yaml"
  ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f $REMOTE_K8S_DIR/storage-class.yaml -f $REMOTE_K8S_DIR/namespace.yaml"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -'
  apply_secret
  apply_jenkins_bootstrap_secret
  ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f $REMOTE_K8S_DIR/jenkins-kubeconfig.yaml"
  ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f $REMOTE_K8S_DIR/mysql-pv-pvc.yaml -f $REMOTE_K8S_DIR/jenkins-pv-pvc.yaml"
  ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f $REMOTE_K8S_DIR/jenkins.yaml"
  ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f $REMOTE_K8S_DIR/mysql.yaml -f $REMOTE_K8S_DIR/backend.yaml -f $REMOTE_K8S_DIR/frontend.yaml -f $REMOTE_K8S_DIR/ingress.yaml"

  log "Waiting for application rollouts"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n app rollout status deployment/mysql --timeout=300s'
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n app rollout status deployment/backend --timeout=300s'
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n app rollout status deployment/frontend --timeout=300s'
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n jenkins rollout status deployment/jenkins --timeout=300s'
}

wait_for_jenkins_build() {
  log "Waiting for Jenkins first Pipeline build"
  local attempt
  local status
  for attempt in {1..120}; do
    status="$(ssh_root_command "$MASTER_HOST" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n jenkins exec deployment/jenkins -- sh -c 'curl -fsS --user \"\$JENKINS_ADMIN_USER:\$JENKINS_ADMIN_PASSWORD\" http://127.0.0.1:8080/job/\"\$JENKINS_JOB_NAME\"/lastBuild/api/json'" 2>/dev/null || true)"
    if [[ "$status" == *'"building":false'* && "$status" == *'"result":"SUCCESS"'* ]]; then
      log "Jenkins first Pipeline build succeeded"
      return
    fi
    if [[ "$status" == *'"building":false'* && "$status" != *'"result":"SUCCESS"'* ]]; then
      die "Jenkins first Pipeline build did not succeed; inspect http://$MASTER_HOST:30081/job/$JENKINS_JOB_NAME/"
    fi
    sleep 10
  done
  die "Timed out waiting for Jenkins first Pipeline build; inspect http://$MASTER_HOST:30081/job/$JENKINS_JOB_NAME/"
}

collect_node_evidence() {
  local role=$1
  local host=$2
  local output_file=$3

  ssh_root_command "$host" 'hostnamectl status; printf "\n--- timezone ---\n"; timedatectl status; printf "\n--- kernel ---\n"; uname -a; printf "\n--- disk ---\n"; df -h; printf "\n--- network addresses ---\n"; ip -br address; printf "\n--- listening TCP ports ---\n"; ss -lnt' >"$output_file"
  log "Collected $role evidence: $output_file"
}

collect_assessment_evidence() {
  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  EVIDENCE_DIR="$REPO_ROOT/deployment/evidence/$timestamp"
  mkdir -p "$EVIDENCE_DIR"

  cat >"$EVIDENCE_DIR/servers.txt" <<EOF
timezone=$TIMEZONE
master_ssh_host=$MASTER_HOST
master_private_ip=$MASTER_PRIVATE_IP
node_01_ssh_host=$NODE01_HOST
node_01_private_ip=$NODE01_PRIVATE_IP
node_02_ssh_host=$NODE02_HOST
node_02_private_ip=$NODE02_PRIVATE_IP
EOF

  log "Collecting assessment evidence"
  collect_node_evidence master "$MASTER_HOST" "$EVIDENCE_DIR/master-system.txt"
  collect_node_evidence node-01 "$NODE01_HOST" "$EVIDENCE_DIR/node-01-system.txt"
  collect_node_evidence node-02 "$NODE02_HOST" "$EVIDENCE_DIR/node-02-system.txt"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide' >"$EVIDENCE_DIR/kubectl-nodes.txt"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A' >"$EVIDENCE_DIR/kubectl-pods.txt"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get svc -A' >"$EVIDENCE_DIR/kubectl-services.txt"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get ingress -A' >"$EVIDENCE_DIR/kubectl-ingress.txt"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pvc -A' >"$EVIDENCE_DIR/kubectl-pvcs.txt"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get storageclass' >"$EVIDENCE_DIR/kubectl-storageclasses.txt"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n app get secret mysql-secret' >"$EVIDENCE_DIR/kubectl-mysql-secret.txt"
  ssh_root_command "$MASTER_HOST" 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n jenkins get secret jenkins-bootstrap' >"$EVIDENCE_DIR/kubectl-jenkins-secret.txt"
  cp "$REPO_ROOT/deployment/ports.md" "$EVIDENCE_DIR/ports.md"
  log "Assessment evidence saved to $EVIDENCE_DIR"
}

print_plan() {
  cat <<PLAN
Deployment plan:
  master SSH:        $SSH_USER@$MASTER_HOST:$SSH_PORT
  master private IP: $MASTER_PRIVATE_IP
  node-01 SSH:       $SSH_USER@$NODE01_HOST:$SSH_PORT
  node-01 private:   $NODE01_PRIVATE_IP
  node-02 SSH:       $SSH_USER@$NODE02_HOST:$SSH_PORT
  node-02 private:   $NODE02_PRIVATE_IP
  Kubernetes minor:  $K8S_MINOR
  Timezone:          $TIMEZONE
  Calico:            $CALICO_VERSION
  Ingress:           $INGRESS_NGINX_VERSION
  Headlamp version:  $HEADLAMP_VERSION
  Headlamp:          $INSTALL_HEADLAMP
  Jenkins job:       $JENKINS_JOB_NAME
  GitHub repository: $GITHUB_REPOSITORY_URL
PLAN
}

print_plan
if [[ "$DRY_RUN" == 1 ]]; then
  log "Dry run complete; no server was changed"
  exit 0
fi

check_ssh
prepare_node "$MASTER_HOST" master yes
prepare_node "$NODE01_HOST" node-01 no
prepare_node "$NODE02_HOST" node-02 no
init_master
join_worker "$NODE01_HOST" node-01
join_worker "$NODE02_HOST" node-02
configure_nfs
install_addons
verify_cluster
deploy_resources
wait_for_jenkins_build
collect_assessment_evidence

log "Deployment complete"
cat <<SUMMARY
Application ingress: http://$MASTER_HOST:30080
Jenkins:             http://$MASTER_HOST:30081
Kubernetes API:      $MASTER_PRIVATE_IP:6443

Jenkins administrator: $JENKINS_ADMIN_USER
Jenkins Pipeline:      $JENKINS_JOB_NAME
Jenkins first build:   succeeded

Next step:
  Review $EVIDENCE_DIR and capture browser screenshots required by the assessment.
SUMMARY

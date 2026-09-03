#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
HOSTS_FILE="$SCRIPT_DIR/hosts.env"
SECRETS_FILE="$SCRIPT_DIR/secrets.env"
EVIDENCE_ROOT="$SCRIPT_DIR/evidence"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  ./deployment/verify-acceptance.sh --check
  ./deployment/verify-acceptance.sh --exercise-recovery [--yes]

--check verifies the PPT acceptance resources and saves safe evidence locally.
It does not write data or restart Pods.

--exercise-recovery runs --check first, writes one clearly named demo record,
then deletes the backend and MySQL Pods one at a time. Kubernetes recreates the
Pods; the script verifies that the demo record remains readable. Without --yes,
you must type DELETE_PODS before this destructive demonstration starts.
USAGE
}

load_config() {
  local config_file=$1
  [[ -f "$config_file" ]] || die "missing local config: $config_file"
  set -a
  source "$config_file"
  set +a
}

MODE=''
ASSUME_YES=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --check|--exercise-recovery)
      [[ -z "$MODE" ]] || die "choose only one check mode"
      MODE="$1"
      ;;
    --yes)
      ASSUME_YES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

[[ -n "$MODE" ]] || { usage >&2; exit 1; }
[[ "$MODE" == --exercise-recovery || "$ASSUME_YES" == 0 ]] || die "--yes is valid only with --exercise-recovery"

load_config "$HOSTS_FILE"
load_config "$SECRETS_FILE"

SSH_USER="${SSH_USER-ecs-user}"
SSH_PORT="${SSH_PORT-22}"
SSH_KEY="${SSH_KEY-}"
MASTER_HOST="${MASTER_HOST-}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER-}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD-}"
JENKINS_JOB_NAME="${JENKINS_JOB_NAME-fullstack-pipeline}"

[[ -n "$MASTER_HOST" ]] || die "MASTER_HOST is required in deployment/hosts.env"
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] || die "SSH_KEY must be an existing private-key file"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || die "SSH_PORT must be numeric"
[[ -n "$JENKINS_ADMIN_USER" ]] || die "JENKINS_ADMIN_USER is required in deployment/secrets.env"
[[ -n "$JENKINS_ADMIN_PASSWORD" ]] || die "JENKINS_ADMIN_PASSWORD is required in deployment/secrets.env"

SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
  -p "$SSH_PORT"
  -i "$SSH_KEY"
)
APP_URL="http://$MASTER_HOST:30080"
timestamp="$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="$EVIDENCE_ROOT/acceptance-$timestamp"
mkdir -p "$EVIDENCE_DIR/manifests"

ssh_root_command() {
  local command=$1
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$MASTER_HOST" "sudo -n bash -lc $(printf '%q' "$command")"
}

capture_remote() {
  local output_file=$1
  local command=$2
  ssh_root_command "$command" >"$EVIDENCE_DIR/$output_file"
}

verify_cluster_resources() {
  printf '==> Verifying cluster, storage, network, and workload resources\n'
  capture_remote kubernetes-acceptance.txt '
set -Eeuo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl wait --for=condition=Ready node/master node/node-01 node/node-02 --timeout=180s
kubectl -n kube-system rollout status daemonset/calico-node --timeout=180s
kubectl -n kube-system rollout status deployment/coredns --timeout=180s
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s
kubectl -n kube-system rollout status deployment/headlamp --timeout=180s
ingress_node_port="$(kubectl -n ingress-nginx get service ingress-nginx-controller -o yaml | awk "\$1 == \"nodePort:\" { print \$2 }" | grep -x 30080)"
[[ "$ingress_node_port" == "30080" ]]
kubectl get storageclass nfs-static
kubectl get pv mysql-pv jenkins-pv
kubectl -n app get pvc mysql-pvc
kubectl -n jenkins get pvc jenkins-pvc
kubectl -n app get secret mysql-secret
kubectl -n jenkins get secret jenkins-bootstrap
kubectl -n app get ingress app-ingress
kubectl -n app get svc frontend backend mysql
kubectl -n jenkins get svc jenkins
kubectl -n app rollout status deployment/mysql --timeout=180s
kubectl -n app rollout status deployment/backend --timeout=180s
kubectl -n app rollout status deployment/frontend --timeout=180s
kubectl -n jenkins rollout status deployment/jenkins --timeout=180s
'

  capture_remote kubectl-nodes.txt 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide'
  capture_remote kubectl-pods.txt 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A -o wide'
  capture_remote kubectl-services.txt 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get svc -A'
  capture_remote kubectl-ingress.txt 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get ingress -A'
  capture_remote kubectl-pvcs.txt 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pvc -A'
  capture_remote kubectl-storageclasses.txt 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get storageclass'
  capture_remote nfs-exports.txt 'exportfs -v'
}

verify_public_app() {
  printf '==> Verifying the public Ingress application route\n'
  curl --fail --silent --show-error --connect-timeout 10 --max-time 20 "$APP_URL/api/items" >"$EVIDENCE_DIR/app-items-before.json"
  grep -Eq '^[[:space:]]*\[' "$EVIDENCE_DIR/app-items-before.json" \
    || die "the public API did not return an item list: $APP_URL/api/items"
}

verify_jenkins_build() {
  printf '==> Verifying Jenkins latest Pipeline build\n'
  local admin_user_encoded
  local admin_password_encoded
  admin_user_encoded="$(printf '%s' "$JENKINS_ADMIN_USER" | base64 | tr -d '\n')"
  admin_password_encoded="$(printf '%s' "$JENKINS_ADMIN_PASSWORD" | base64 | tr -d '\n')"

  ssh "${SSH_OPTS[@]}" "$SSH_USER@$MASTER_HOST" 'sudo -n bash -s' <<REMOTE >"$EVIDENCE_DIR/jenkins-last-build.json"
set -Eeuo pipefail
admin_user="\$(printf '%s' '$admin_user_encoded' | base64 -d)"
admin_password="\$(printf '%s' '$admin_password_encoded' | base64 -d)"
credentials_file="\$(mktemp)"
trap 'rm -f "\$credentials_file"' EXIT
chmod 0600 "\$credentials_file"
printf 'machine 127.0.0.1 login %s password %s\n' "\$admin_user" "\$admin_password" >"\$credentials_file"
curl --fail --silent --show-error --netrc-file "\$credentials_file" \
  'http://127.0.0.1:30081/job/$JENKINS_JOB_NAME/lastBuild/api/json'
REMOTE

  grep -Eq '"result"[[:space:]]*:[[:space:]]*"SUCCESS"' "$EVIDENCE_DIR/jenkins-last-build.json" \
    || die "Jenkins latest build is not SUCCESS; inspect http://$MASTER_HOST:30081/job/$JENKINS_JOB_NAME/"
}

collect_manifest_evidence() {
  printf '==> Recording Git and Manifest evidence\n'
  {
    git remote get-url origin
    git rev-parse HEAD
    git status --short
  } >"$EVIDENCE_DIR/git-state.txt"
  cp "$REPO_ROOT/Jenkinsfile" "$EVIDENCE_DIR/manifests/Jenkinsfile"
  cp "$REPO_ROOT/k8s/namespace.yaml" "$REPO_ROOT/k8s/storage-class.yaml" "$REPO_ROOT/k8s/mysql-pv-pvc.yaml" "$REPO_ROOT/k8s/mysql.yaml" "$REPO_ROOT/k8s/backend.yaml" "$REPO_ROOT/k8s/frontend.yaml" "$REPO_ROOT/k8s/ingress.yaml" "$REPO_ROOT/k8s/jenkins.yaml" "$REPO_ROOT/k8s/jenkins-pv-pvc.yaml" "$EVIDENCE_DIR/manifests/"
  cp "$SCRIPT_DIR/ports.md" "$EVIDENCE_DIR/ports.md"
}

wait_for_demo_item() {
  local label=$1
  local output_file=$2
  local attempt
  for attempt in {1..30}; do
    if curl --fail --silent --show-error --connect-timeout 10 --max-time 20 "$APP_URL/api/items" >"$EVIDENCE_DIR/$output_file" 2>/dev/null \
      && grep -Fq "$label" "$EVIDENCE_DIR/$output_file"; then
      return
    fi
    sleep 2
  done
  die "the demo record was not readable after recovery: $label"
}

restart_and_verify_pod() {
  local label=$1
  local record=$2
  local old_pod
  old_pod="$(ssh_root_command "KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n app get pods -l app=$label -o jsonpath='{.items[0].metadata.name}'")"
  [[ "$old_pod" =~ ^[a-z0-9-]+$ ]] || die "could not determine the current $label Pod"
  printf '==> Deleting %s Pod %s for the recovery demonstration\n' "$label" "$old_pod"
  ssh_root_command "KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n app delete pod $old_pod --wait=true" >"$EVIDENCE_DIR/${label}-pod-delete.txt"
  ssh_root_command "KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n app wait --for=condition=Ready pod -l app=$label --timeout=300s" >"$EVIDENCE_DIR/${label}-pod-ready.txt"
  wait_for_demo_item "$record" "app-items-after-${label}-recovery.json"
}

exercise_recovery() {
  if [[ "$ASSUME_YES" == 0 ]]; then
    printf 'This creates one test record and deletes the backend and MySQL Pods. Type DELETE_PODS to continue: ' >&2
    local confirmation
    read -r confirmation
    [[ "$confirmation" == DELETE_PODS ]] || die "recovery demonstration cancelled"
  fi

  local demo_record
  demo_record="acceptance-$(date +%Y%m%d-%H%M%S)"
  printf '==> Writing demo record %s\n' "$demo_record"
  curl --fail --silent --show-error --connect-timeout 10 --max-time 20 \
    --request POST "$APP_URL/api/items" \
    --header 'Content-Type: application/json' \
    --data "{\"name\":\"$demo_record\"}" >"$EVIDENCE_DIR/demo-record-created.json"
  wait_for_demo_item "$demo_record" app-items-after-create.json
  restart_and_verify_pod backend "$demo_record"
  restart_and_verify_pod mysql "$demo_record"
  printf '%s\n' "$demo_record" >"$EVIDENCE_DIR/demo-record-name.txt"
}

verify_cluster_resources
verify_public_app
verify_jenkins_build
collect_manifest_evidence

if [[ "$MODE" == --exercise-recovery ]]; then
  exercise_recovery
fi

printf 'Acceptance %s passed. Evidence: %s\n' "${MODE#--}" "$EVIDENCE_DIR"
printf 'Application: %s\nJenkins: http://%s:30081\n' "$APP_URL" "$MASTER_HOST"

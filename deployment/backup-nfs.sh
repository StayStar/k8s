#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
HOSTS_FILE="$SCRIPT_DIR/hosts.env"
LOCAL_BACKUP_DIR="$SCRIPT_DIR/backups"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  ./deployment/backup-nfs.sh --create
  ./deployment/backup-nfs.sh --list

--create temporarily stops Jenkins, creates a consistent Jenkins archive and a
MySQL logical dump on the master, restarts Jenkins, then downloads the backup
to deployment/backups/ on this Mac. The local backup directory is Git-ignored.
USAGE
}

load_config() {
  local config_file=$1
  [[ -f "$config_file" ]] || die "missing local config: $config_file"
  set -a
  source "$config_file"
  set +a
}

MODE="${1---create}"
case "$MODE" in
  --create|--list) ;;
  -h|--help) usage; exit 0 ;;
  *) die "unknown option: $MODE" ;;
esac
[[ "$#" -eq 1 ]] || die "only one option is supported"

load_config "$HOSTS_FILE"

SSH_USER="${SSH_USER-ubuntu}"
SSH_PORT="${SSH_PORT-22}"
SSH_KEY="${SSH_KEY-}"
MASTER_HOST="${MASTER_HOST-}"

[[ -n "$MASTER_HOST" ]] || die "MASTER_HOST is required in deployment/hosts.env"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || die "SSH_PORT must be numeric"
[[ -n "$SSH_KEY" ]] || die "SSH_KEY must not be empty"
[[ -f "$SSH_KEY" ]] || die "SSH_KEY does not exist: $SSH_KEY"

SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -p $SSH_PORT"
SCP_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -P $SSH_PORT"
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
  SCP_OPTS="$SCP_OPTS -i $SSH_KEY"
fi

ssh_root_command() {
  local command=$1
  ssh $SSH_OPTS "$SSH_USER@$MASTER_HOST" "sudo -n bash -lc $(printf '%q' "$command")"
}

ssh_root_script() {
  ssh $SSH_OPTS "$SSH_USER@$MASTER_HOST" sudo -n bash -s -- "$@"
}

if [[ "$MODE" == --list ]]; then
  ssh_root_command "find /srv/nfs/backups -mindepth 1 -maxdepth 1 -type d -name 'fullstack-*' -printf '%f\\n' 2>/dev/null | sort"
  exit 0
fi

backup_name="fullstack-$(date +%Y%m%d-%H%M%S)"
remote_backup_dir="/srv/nfs/backups/$backup_name"
mkdir -p "$LOCAL_BACKUP_DIR"

printf '==> Creating backup %s on the master\n' "$backup_name"
ssh_root_script "$remote_backup_dir" "$SSH_USER" <<'REMOTE'
set -Eeuo pipefail
backup_dir="$1"
ssh_user="$2"
export KUBECONFIG=/etc/kubernetes/admin.conf

jenkins_replicas="$(kubectl -n jenkins get deployment/jenkins -o jsonpath='{.spec.replicas}')"
[[ "$jenkins_replicas" =~ ^[0-9]+$ ]] || { echo 'Cannot determine Jenkins replica count' >&2; exit 1; }

restore_jenkins() {
  if [[ "$jenkins_replicas" -gt 0 ]]; then
    kubectl -n jenkins scale deployment/jenkins --replicas="$jenkins_replicas" >/dev/null 2>&1 || true
  fi
}
trap restore_jenkins EXIT

if [[ "$jenkins_replicas" -gt 0 ]]; then
  kubectl -n jenkins scale deployment/jenkins --replicas=0 >/dev/null
  for attempt in {1..60}; do
    pod_count="$(kubectl -n jenkins get pods -l app=jenkins --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$pod_count" == 0 ]] && break
    sleep 5
  done
  [[ "${pod_count-}" == 0 ]] || { echo 'Timed out waiting for Jenkins to stop' >&2; exit 1; }
fi

install -d -m 0750 "$backup_dir"
kubectl -n app exec deployment/mysql -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot --single-transaction --routines --events --add-drop-database --databases "$MYSQL_DATABASE"' \
  | gzip -c >"$backup_dir/mysql.sql.gz"
tar --numeric-owner --xattrs --acls -C /srv/nfs -czf "$backup_dir/jenkins-home.tar.gz" jenkins
kubectl get nodes -o wide >"$backup_dir/nodes.txt"
kubectl get pvc -A >"$backup_dir/pvcs.txt"
printf 'created_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$backup_dir/backup-info.txt"
sha256sum "$backup_dir"/* >"$backup_dir/SHA256SUMS"
chown -R "$ssh_user:$ssh_user" "$backup_dir"
REMOTE

printf '==> Downloading backup to %s\n' "$LOCAL_BACKUP_DIR"
scp $SCP_OPTS -r "$SSH_USER@$MASTER_HOST:$remote_backup_dir" "$LOCAL_BACKUP_DIR/"
printf 'Backup complete: %s/%s\n' "$LOCAL_BACKUP_DIR" "$backup_name"

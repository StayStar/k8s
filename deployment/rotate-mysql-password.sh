#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
HOSTS_FILE="$SCRIPT_DIR/hosts.env"
SECRETS_FILE="$SCRIPT_DIR/secrets.env"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  ./deployment/rotate-mysql-password.sh --app [--dry-run]
  ./deployment/rotate-mysql-password.sh --root [--dry-run]
  ./deployment/rotate-mysql-password.sh --all [--dry-run]

Before running, create a backup and edit deployment/secrets.env:
  --app   Change only MYSQL_PASSWORD. MYSQL_ROOT_PASSWORD must remain current.
  --root  Change only MYSQL_ROOT_PASSWORD. The script securely asks for the current root password.
  --all   Change both passwords. The script securely asks for the current root password.

The non-dry-run command briefly restarts MySQL, backend, and Jenkins so each
service receives the new Kubernetes Secret values. It never prints passwords.
USAGE
}

load_config() {
  local config_file=$1
  [[ -f "$config_file" ]] || die "missing local config: $config_file"
  set -a
  source "$config_file"
  set +a
}

require_safe_password() {
  local name=$1
  local value=$2
  [[ -n "$value" ]] || die "$name must not be empty"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *"'"* ]] \
    || die "$name must not contain a single quote or a line break"
}

MODE=''
DRY_RUN=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --app|--root|--all)
      [[ -z "$MODE" ]] || die "choose only one of --app, --root, or --all"
      MODE="$1"
      ;;
    --dry-run)
      DRY_RUN=1
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

load_config "$HOSTS_FILE"
load_config "$SECRETS_FILE"

SSH_USER="${SSH_USER-ecs-user}"
SSH_PORT="${SSH_PORT-22}"
SSH_KEY="${SSH_KEY-}"
MASTER_HOST="${MASTER_HOST-}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD-}"
MYSQL_PASSWORD="${MYSQL_PASSWORD-}"
MYSQL_DATABASE="${MYSQL_DATABASE-appdb}"
MYSQL_USER="${MYSQL_USER-app}"

[[ -n "$MASTER_HOST" ]] || die "MASTER_HOST is required in deployment/hosts.env"
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] || die "SSH_KEY must be an existing private-key file"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || die "SSH_PORT must be numeric"
[[ "$MYSQL_DATABASE" =~ ^[A-Za-z0-9_]+$ ]] || die "MYSQL_DATABASE has an unsupported value"
[[ "$MYSQL_USER" =~ ^[A-Za-z0-9_]+$ ]] || die "MYSQL_USER has an unsupported value"
require_safe_password MYSQL_ROOT_PASSWORD "$MYSQL_ROOT_PASSWORD"
require_safe_password MYSQL_PASSWORD "$MYSQL_PASSWORD"
[[ "$MYSQL_ROOT_PASSWORD" != "$MYSQL_PASSWORD" ]] || die "MySQL root and application passwords must differ"

SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
  -p "$SSH_PORT"
  -i "$SSH_KEY"
)

ssh_root_command() {
  local command=$1
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$MASTER_HOST" "sudo -n bash -lc $(printf '%q' "$command")"
}

if [[ "$DRY_RUN" == 1 ]]; then
  printf 'Password rotation plan: %s\n' "$MODE"
  printf 'Master: %s@%s:%s\n' "$SSH_USER" "$MASTER_HOST" "$SSH_PORT"
  printf 'Would update MySQL, mysql-secret, jenkins-bootstrap, and restart MySQL, backend, and Jenkins.\n'
  exit 0
fi

CURRENT_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
if [[ "$MODE" != --app ]]; then
  printf 'Enter the CURRENT MySQL root password: ' >&2
  IFS= read -r -s CURRENT_ROOT_PASSWORD
  printf '\n' >&2
  require_safe_password CURRENT_MYSQL_ROOT_PASSWORD "$CURRENT_ROOT_PASSWORD"
fi

current_root_password_encoded="$(printf '%s' "$CURRENT_ROOT_PASSWORD" | base64 | tr -d '\n')"
desired_root_password_encoded="$(printf '%s' "$MYSQL_ROOT_PASSWORD" | base64 | tr -d '\n')"
desired_app_password_encoded="$(printf '%s' "$MYSQL_PASSWORD" | base64 | tr -d '\n')"

running_root_password_encoded="$(ssh_root_command "KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n app get secret mysql-secret -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}'")"
running_app_password_encoded="$(ssh_root_command "KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n app get secret mysql-secret -o jsonpath='{.data.MYSQL_PASSWORD}'")"
[[ -n "$running_root_password_encoded" && -n "$running_app_password_encoded" ]] \
  || die "the running mysql-secret is missing required password keys"

case "$MODE" in
  --app)
    [[ "$desired_root_password_encoded" == "$running_root_password_encoded" ]] \
      || die "--app requires MYSQL_ROOT_PASSWORD to remain unchanged; use --all to rotate both passwords"
    ;;
  --root)
    [[ "$desired_app_password_encoded" == "$running_app_password_encoded" ]] \
      || die "--root requires MYSQL_PASSWORD to remain unchanged; use --all to rotate both passwords"
    ;;
esac

printf '==> Verifying MySQL and changing credentials\n'
ssh "${SSH_OPTS[@]}" "$SSH_USER@$MASTER_HOST" 'sudo -n bash -s' <<REMOTE
set -Eeuo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

mode='$MODE'
mysql_user='$MYSQL_USER'
current_root_password_encoded='$current_root_password_encoded'
desired_root_password_encoded='$desired_root_password_encoded'
desired_app_password_encoded='$desired_app_password_encoded'

decode() {
  printf '%s' "\$1" | base64 -d
}

mysql_literal() {
  local value="\$1"
  value="\${value//\\\\/\\\\\\\\}"
  value="\${value//\'/\\\'}"
  printf "'%s'" "\$value"
}

mysql_as_root() {
  local password="\$1"
  local sql="\$2"
  printf '%s\n%s\n' "\$password" "\$sql" \
    | kubectl -n app exec -i deployment/mysql -- sh -c 'IFS= read -r password; MYSQL_PWD="\$password" exec mysql -uroot --protocol=socket --batch --skip-column-names'
}

current_root_password="\$(decode "\$current_root_password_encoded")"
desired_root_password="\$(decode "\$desired_root_password_encoded")"
desired_app_password="\$(decode "\$desired_app_password_encoded")"

kubectl -n app rollout status deployment/mysql --timeout=180s >/dev/null
mysql_as_root "\$current_root_password" 'SELECT 1;' >/dev/null

case "\$mode" in
  --app)
    mysql_as_root "\$current_root_password" "ALTER USER '\$mysql_user'@'%' IDENTIFIED BY \$(mysql_literal "\$desired_app_password");"
    ;;
  --root)
    mysql_as_root "\$current_root_password" "ALTER USER 'root'@'localhost' IDENTIFIED BY \$(mysql_literal "\$desired_root_password");"
    ;;
  --all)
    mysql_as_root "\$current_root_password" "ALTER USER 'root'@'localhost' IDENTIFIED BY \$(mysql_literal "\$desired_root_password"); ALTER USER '\$mysql_user'@'%' IDENTIFIED BY \$(mysql_literal "\$desired_app_password");"
    ;;
  *)
    echo "Unknown rotation mode" >&2
    exit 1
    ;;
esac
REMOTE

printf '==> Updating Kubernetes Secret resources\n'
cat <<EOF | ssh "${SSH_OPTS[@]}" "$SSH_USER@$MASTER_HOST" 'sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -' >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: app
type: Opaque
data:
  MYSQL_ROOT_PASSWORD: $desired_root_password_encoded
  MYSQL_DATABASE: $(printf '%s' "$MYSQL_DATABASE" | base64 | tr -d '\n')
  MYSQL_USER: $(printf '%s' "$MYSQL_USER" | base64 | tr -d '\n')
  MYSQL_PASSWORD: $desired_app_password_encoded
EOF

ssh "${SSH_OPTS[@]}" "$SSH_USER@$MASTER_HOST" 'sudo -n bash -s' <<REMOTE
set -Eeuo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl -n jenkins patch secret jenkins-bootstrap --type=merge --patch '{"data":{"MYSQL_ROOT_PASSWORD":"$desired_root_password_encoded","MYSQL_PASSWORD":"$desired_app_password_encoded"}}' >/dev/null
kubectl -n app rollout restart deployment/mysql
kubectl -n app rollout status deployment/mysql --timeout=300s
kubectl -n app rollout restart deployment/backend
kubectl -n app rollout status deployment/backend --timeout=300s
kubectl -n jenkins rollout restart deployment/jenkins
kubectl -n jenkins rollout status deployment/jenkins --timeout=300s
REMOTE

printf 'Password rotation complete. The new values are now active; do not rerun ./deployment/deploy.sh to change passwords.\n'

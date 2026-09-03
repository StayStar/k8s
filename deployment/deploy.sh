#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
HOSTS_FILE="$SCRIPT_DIR/hosts.env"
SECRETS_FILE="$SCRIPT_DIR/secrets.env"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  1. Fill deployment/hosts.env. Every field has a Chinese explanation and example.
  2. Fill deployment/secrets.env. Every field has a Chinese explanation and example.
  3. Run ./deployment/deploy.sh --dry-run to validate the values only.
  4. Run ./deployment/deploy.sh to provision servers and create the first Jenkins build.

The script creates Jenkins credentials, the Pipeline job, and its first build.
It writes secret values to Kubernetes Secret resources, never to Git-tracked YAML.
USAGE
}

if [[ "$#" -gt 0 && ( "$1" == -h || "$1" == --help ) ]]; then
  usage
  exit 0
fi

load_config() {
  local config_file=$1
  [[ -f "$config_file" ]] || die "missing local config: $config_file"
  set -a
  source "$config_file"
  set +a
}

load_config "$HOSTS_FILE"
load_config "$SECRETS_FILE"

retry_command() {
  local label=$1
  shift
  local attempt
  local max_attempts=5

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if "$@"; then
      return 0
    fi
    if (( attempt == max_attempts )); then
      break
    fi
    printf 'WARNING: %s failed; retrying in 15 seconds (%d/%d)\n' "$label" "$attempt" "$max_attempts" >&2
    sleep 15
  done

  return 1
}

docker_hub_login() {
  printf '%s' "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin
}

command -v docker >/dev/null 2>&1 || die "Docker Desktop command not found: docker"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME-staystar}"

if [[ "${1-}" == --dry-run ]]; then
  exec "$SCRIPT_DIR/deploy-cluster.sh" "$@"
fi

"$SCRIPT_DIR/deploy-cluster.sh" --dry-run

if ! retry_command "Docker Hub login" docker_hub_login; then
  exit 1
fi
if ! retry_command "Jenkins image build" docker build --platform linux/amd64 -t "$DOCKERHUB_USERNAME/fullstack-jenkins:latest" "$REPO_ROOT/jenkins"; then
  docker logout >/dev/null 2>&1 || true
  exit 1
fi
if ! retry_command "Jenkins image push" docker push "$DOCKERHUB_USERNAME/fullstack-jenkins:latest"; then
  docker logout >/dev/null 2>&1 || true
  exit 1
fi
docker logout >/dev/null

exec "$SCRIPT_DIR/deploy-cluster.sh" "$@"

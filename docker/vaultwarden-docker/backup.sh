#!/bin/bash
#  ____  _ _                         _
# | __ )(_) |___      ____ _ _ __ __| | ___ _ __
# |  _ \| | __\ \ /\ / / _` | '__/ _` |/ _ \ '_ \
# | |_) | | |_ \ V  V / (_| | | | (_| |  __/ | | |
# |____/|_|\__| \_/\_/ \__,_|_|  \__,_|\___|_| |_|
#  ____             _
# | __ )  __ _  ___| | ___   _ _ __
# |  _ \ / _` |/ __| |/ / | | | '_ \
# | |_) | (_| | (__|   <| |_| | |_) |
# |____/ \__,_|\___|_|\_\\__,_| .__/
#                             |_|
# This script requires zstd to work properly. 
set -euo pipefail

# --- Configuration ---------------------------------------------------------
COMPOSE_FILE="./docker-compose.yml"
CONTAINER_NAME="vaultwarden"
SERVICE_NAME="vaultwarden"
BACKUP_SCRIPT="./backup.sh"          # your existing backup script

# Health check hits Vaultwarden's /alive endpoint directly on its bound port.
HEALTH_URL="http://192.168.100.99:8000/alive"
HEALTH_RETRIES=10
HEALTH_RETRY_INTERVAL=3

# ntfy.sh notifications
NTFY_URL="https://ntfy.sh"
NTFY_TOPIC="vaultwarden_0C6G0aBqeeuDc982"   # <-- fill in your ntfy.sh topic

# ----------------------------------------------------------------------------

cd "$(dirname "$0")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

notify() {
  # notify <title> <message> <priority: min|low|default|high|urgent> [tags]
  local title="$1" message="$2" priority="${3:-default}" tags="${4:-}"
  curl -fsS \
    -H "Title: $title" \
    -H "Priority: $priority" \
    ${tags:+-H "Tags: $tags"} \
    -d "$message" \
    "$NTFY_URL/$NTFY_TOPIC" >/dev/null 2>&1 || log "WARNING: ntfy notification failed to send."
}

on_error() {
  local exit_code=$?
  local line_no=$1
  log "ERROR: command failed at line $line_no (exit code $exit_code)."
  notify "Vaultwarden update FAILED" \
    "Unexpected error at line $line_no (exit $exit_code). Check CI logs." \
    "urgent" "warning,rotating_light"
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

wait_for_healthy() {
  # Waits for the container to report Running, then polls the /alive endpoint.
  local running=false
  for i in $(seq 1 "$HEALTH_RETRIES"); do
    if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" == "true" ]]; then
      running=true
      break
    fi
    sleep "$HEALTH_RETRY_INTERVAL"
  done
  [[ "$running" == "true" ]] || return 1

  for i in $(seq 1 "$HEALTH_RETRIES"); do
    if curl -fsS -o /dev/null "$HEALTH_URL"; then
      return 0
    fi
    sleep "$HEALTH_RETRY_INTERVAL"
  done
  return 1
}

rollback() {
  local previous_commit="$1"
  log "Rolling back to previous commit $previous_commit..."
  notify "Vaultwarden update failed, rolling back" \
    "Health check failed after update. Reverting to previous commit and redeploying." \
    "high" "rewind"

  git reset --hard "$previous_commit"
  docker compose -f "$COMPOSE_FILE" up -d

  if wait_for_healthy; then
    log "Rollback successful, previous version is healthy again."
    notify "Vaultwarden rollback successful" \
      "Reverted to previous commit ($previous_commit) and it's healthy." \
      "high" "white_check_mark"
  else
    log "Rollback FAILED — container is not healthy on the previous version either."
    docker logs "$CONTAINER_NAME" --tail 50 || true
    notify "Vaultwarden ROLLBACK FAILED — manual intervention needed" \
      "Neither the new image nor the rollback to $previous_commit are healthy. SSH in now." \
      "urgent" "rotating_light,skull"
    exit 1
  fi
}

# --- Main --------------------------------------------------------------

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Compose file not found: $COMPOSE_FILE" >&2
  exit 1
fi

CURRENT_COMMIT=$(git rev-parse HEAD)

log "Pulling latest changes from repo..."
git pull origin main

# Image actually running right now, as ground truth (normalized to full digest).
RUNNING_IMAGE_ID=$(docker inspect -f '{{.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "")

log "Pulling latest image..."
docker compose -f "$COMPOSE_FILE" pull

# Image the (possibly updated) compose file now points to, normalized the same way.
NEW_IMAGE_SHORT=$(docker compose -f "$COMPOSE_FILE" images -q "$SERVICE_NAME")
NEW_IMAGE_ID=$(docker image inspect -f '{{.Id}}' "$NEW_IMAGE_SHORT")

if [[ -n "$RUNNING_IMAGE_ID" && "$RUNNING_IMAGE_ID" == "$NEW_IMAGE_ID" ]]; then
  log "Already running the latest image. Nothing to do."
  exit 0
fi

log "New image detected, running backup before updating..."
if [[ -x "$BACKUP_SCRIPT" ]]; then
  if ! "$BACKUP_SCRIPT"; then
    log "Backup script failed — aborting update, leaving current container untouched."
    notify "Vaultwarden update aborted" \
      "backup.sh failed before the update started. No changes were made." \
      "urgent" "warning"
    exit 1
  fi
  log "Backup completed."
else
  log "Backup script not found or not executable at $BACKUP_SCRIPT — aborting update."
  notify "Vaultwarden update aborted" \
    "backup.sh missing or not executable at $BACKUP_SCRIPT. No changes were made." \
    "urgent" "warning"
  exit 1
fi

log "Updating container..."
docker compose -f "$COMPOSE_FILE" up -d

log "Waiting for container to become healthy..."
if wait_for_healthy; then
  log "Vaultwarden updated successfully."
  notify "Vaultwarden updated successfully" \
    "Now running a new image and passing health checks." \
    "default" "white_check_mark"
else
  log "Container failed to become healthy after update."
  docker logs "$CONTAINER_NAME" --tail 50 || true
  rollback "$CURRENT_COMMIT"
fi

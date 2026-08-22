#!/bin/bash

set -euo pipefail

# --- Configuration ---------------------------------------------------------

COMPOSE_FILE="./docker-compose.yml"

CONTAINER_NAME="vaultwarden"
SERVICE_NAME="vaultwarden"

BACKUP_SCRIPT="./backup.sh"

# Vaultwarden /alive endpoint
HEALTH_URL="http://192.168.100.99:8000/alive"
HEALTH_RETRIES=10
HEALTH_RETRY_INTERVAL=3

# ntfy.sh notifications
NTFY_URL="https://ntfy.sh"
NTFY_TOPIC="vaultwarden_0C6G0aBqeeuDc982"

# ---------------------------------------------------------------------------

cd "$(dirname "$0")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

notify() {
    # notify <title> <message> <priority> [tags]

    local title="$1"
    local message="$2"
    local priority="${3:-default}"
    local tags="${4:-}"

    curl -fsS \
        -H "Title: $title" \
        -H "Priority: $priority" \
        ${tags:+-H "Tags: $tags"} \
        -d "$message" \
        "$NTFY_URL/$NTFY_TOPIC" >/dev/null 2>&1 \
        || log "WARNING: ntfy notification failed to send."
}

on_error() {
    local exit_code=$?
    local line_no=$1

    log "ERROR: command failed at line $line_no (exit code $exit_code)."

    notify \
        "Vaultwarden update FAILED" \
        "Unexpected error at line $line_no (exit $exit_code). Check CI logs." \
        "urgent" \
        "warning,rotating_light"

    exit "$exit_code"
}

trap 'on_error $LINENO' ERR

wait_for_healthy() {
    log "Waiting for Vaultwarden container to start..."

    for ((i=1; i<=HEALTH_RETRIES; i++)); do
        if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" == "true" ]]; then
            break
        fi

        sleep "$HEALTH_RETRY_INTERVAL"
    done

    if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" != "true" ]]; then
        return 1
    fi

    log "Container is running. Checking /alive endpoint..."

    for ((i=1; i<=HEALTH_RETRIES; i++)); do
        if curl -fsS -o /dev/null "$HEALTH_URL"; then
            return 0
        fi

        sleep "$HEALTH_RETRY_INTERVAL"
    done

    return 1
}

rollback() {
    local previous_commit="$1"
    local previous_image_id="$2"
    local previous_image_ref="$3"

    log "Rolling back to previous commit $previous_commit..."

    notify \
        "Vaultwarden update failed, rolling back" \
        "Health check failed after update. Reverting to previous commit and Docker image." \
        "high" \
        "rewind"

    git reset --hard "$previous_commit"

    # Restore the exact Docker image that was running before the update.
    if [[ -n "$previous_image_ref" && -n "$previous_image_id" ]]; then
        log "Restoring previous Docker image: $previous_image_ref"

        docker tag "$previous_image_id" "$previous_image_ref"
    fi

    log "Starting previous Vaultwarden version..."

    docker compose -f "$COMPOSE_FILE" up -d --pull never

    if wait_for_healthy; then
        log "Rollback successful. Previous version is healthy again."

        notify \
            "Vaultwarden rollback successful" \
            "Reverted to previous commit ($previous_commit) and restored the previous Docker image." \
            "high" \
            "white_check_mark"
    else
        log "Rollback FAILED — previous version is not healthy."

        docker logs "$CONTAINER_NAME" --tail 50 || true

        notify \
            "Vaultwarden ROLLBACK FAILED — manual intervention needed" \
            "Neither the new image nor the rollback is healthy. SSH in now." \
            "urgent" \
            "rotating_light,skull"

        exit 1
    fi
}

# --- Main -----------------------------------------------------------------

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "Compose file not found: $COMPOSE_FILE" >&2
    exit 1
fi

CURRENT_COMMIT=$(git rev-parse HEAD)

# Capture the exact image currently running BEFORE anything changes.
RUNNING_IMAGE_ID=$(docker inspect \
    -f '{{.Image}}' \
    "$CONTAINER_NAME" \
    2>/dev/null || echo "")

RUNNING_IMAGE_REF=$(docker inspect \
    -f '{{.Config.Image}}' \
    "$CONTAINER_NAME" \
    2>/dev/null || echo "")

log "Current commit: $CURRENT_COMMIT"
log "Current image: ${RUNNING_IMAGE_REF:-unknown}"
log "Current image ID: ${RUNNING_IMAGE_ID:-unknown}"

log "Pulling latest changes from repo..."

git pull --ff-only origin main

NEW_COMMIT=$(git rev-parse HEAD)

if [[ "$CURRENT_COMMIT" == "$NEW_COMMIT" ]]; then
    log "No Git changes detected."
else
    log "Repository updated:"
    log "  $CURRENT_COMMIT"
    log "  -> $NEW_COMMIT"
fi

log "Pulling latest Docker image..."

docker compose -f "$COMPOSE_FILE" pull

# Get the image referenced by the updated compose configuration.
NEW_IMAGE_ID=$(docker compose -f "$COMPOSE_FILE" images -q "$SERVICE_NAME")

if [[ -z "$NEW_IMAGE_ID" ]]; then
    log "ERROR: Could not determine the new image ID."
    exit 1
fi

NEW_IMAGE_ID=$(docker image inspect \
    -f '{{.Id}}' \
    "$NEW_IMAGE_ID")

log "New image ID: $NEW_IMAGE_ID"

# Nothing changed at the Docker image level.
if [[ -n "$RUNNING_IMAGE_ID" && "$RUNNING_IMAGE_ID" == "$NEW_IMAGE_ID" ]]; then
    log "Already running the latest image. Nothing to do."
    exit 0
fi

log "New image detected."

# --- Backup ----------------------------------------------------------------

log "Running backup before updating..."

if [[ -x "$BACKUP_SCRIPT" ]]; then

    if ! "$BACKUP_SCRIPT"; then
        log "Backup script failed — aborting update."

        notify \
            "Vaultwarden update aborted" \
            "backup.sh failed before the update started. No changes were made." \
            "urgent" \
            "warning"

        exit 1
    fi

    log "Backup completed."

else

    log "Backup script not found or not executable: $BACKUP_SCRIPT"

    notify \
        "Vaultwarden update aborted" \
        "backup.sh missing or not executable at $BACKUP_SCRIPT. No changes were made." \
        "urgent" \
        "warning"

    exit 1
fi

# --- Update ----------------------------------------------------------------

log "Updating Vaultwarden container..."

docker compose -f "$COMPOSE_FILE" up -d

log "Waiting for container to become healthy..."

if wait_for_healthy; then

    log "Vaultwarden updated successfully."

    notify \
        "Vaultwarden updated successfully" \
        "Vaultwarden is running the new image and passing health checks." \
        "default" \
        "white_check_mark"

else

    log "Container failed health checks after update."

    docker logs "$CONTAINER_NAME" --tail 50 || true

    rollback \
        "$CURRENT_COMMIT" \
        "$RUNNING_IMAGE_ID" \
        "$RUNNING_IMAGE_REF"
fi
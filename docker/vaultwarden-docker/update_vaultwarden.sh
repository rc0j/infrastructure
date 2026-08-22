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

    log "Container is running. Checking /alive..."

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
    local previous_image="$2"

    log "Rolling back to commit $previous_commit..."

    notify \
        "Vaultwarden update failed, rolling back" \
        "Health check failed after update. Reverting to the previous version." \
        "high" \
        "rewind"

    git reset --hard "$previous_commit"

    log "Restoring previous image: $previous_image"

    # Make sure the old image is available locally.
    if ! docker image inspect "$previous_image" >/dev/null 2>&1; then
        log "Previous image is no longer available locally. Pulling $previous_image..."
        docker pull "$previous_image"
    fi

    # Start the exact previous Compose configuration.
    docker compose -f "$COMPOSE_FILE" up -d --pull never

    if wait_for_healthy; then
        log "Rollback successful. Previous version is healthy again."

        notify \
            "Vaultwarden rollback successful" \
            "Reverted to commit $previous_commit and restored $previous_image." \
            "high" \
            "white_check_mark"
    else
        log "Rollback FAILED — previous version is not healthy."

        docker logs "$CONTAINER_NAME" --tail 50 || true

        notify \
            "Vaultwarden ROLLBACK FAILED — manual intervention needed" \
            "Neither the new version nor the rollback is healthy. SSH in now." \
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

# ---------------------------------------------------------------------------
# Capture the currently running image BEFORE pulling Git changes.
# ---------------------------------------------------------------------------

RUNNING_IMAGE=$(docker inspect \
    -f '{{.Config.Image}}' \
    "$CONTAINER_NAME" \
    2>/dev/null || echo "")

log "Current commit: $CURRENT_COMMIT"
log "Currently running image: ${RUNNING_IMAGE:-none}"

# ---------------------------------------------------------------------------
# Pull latest Git changes.
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Determine which image the updated Compose file wants to use.
# ---------------------------------------------------------------------------

NEW_IMAGE=$(docker compose -f "$COMPOSE_FILE" config --images \
    | grep -E '/server:' \
    | head -n1)

if [[ -z "$NEW_IMAGE" ]]; then
    log "ERROR: Could not determine Vaultwarden image from Compose file."
    exit 1
fi

log "Compose image: $NEW_IMAGE"

# ---------------------------------------------------------------------------
# Compare the actual running image with the Compose image.
# ---------------------------------------------------------------------------

if [[ -n "$RUNNING_IMAGE" && "$RUNNING_IMAGE" == "$NEW_IMAGE" ]]; then
    log "Already running $NEW_IMAGE. Nothing to do."
    exit 0
fi

log "New image detected:"
log "  Current: $RUNNING_IMAGE"
log "  Target:  $NEW_IMAGE"

# ---------------------------------------------------------------------------
# Pull the new image.
# ---------------------------------------------------------------------------

log "Pulling latest image..."

docker compose -f "$COMPOSE_FILE" pull

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------

log "Updating Vaultwarden container..."

docker compose -f "$COMPOSE_FILE" up -d --pull never

log "Waiting for container to become healthy..."

if wait_for_healthy; then

    log "Vaultwarden updated successfully."

    notify \
        "Vaultwarden updated successfully" \
        "Vaultwarden is now running $NEW_IMAGE and passing health checks." \
        "default" \
        "white_check_mark"

else

    log "Container failed health checks after update."

    docker logs "$CONTAINER_NAME" --tail 50 || true

    rollback \
        "$CURRENT_COMMIT" \
        "$RUNNING_IMAGE"
fi
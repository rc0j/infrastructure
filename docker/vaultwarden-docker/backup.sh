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

COMPOSE_FILE="./docker-compose.yml"
CONTAINER_NAME="vaultwarden"
SERVICE_NAME="vaultwarden"

cd "$(dirname "$0")"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Compose file not found: $COMPOSE_FILE" >&2
  exit 1
fi

echo "Pulling latest changes from repo..."
git pull origin main

# Get the current image ID for the service BEFORE pulling, so the
# comparison uses the same ID format as the post-pull check.
OLD_IMAGE_ID=$(docker compose -f "$COMPOSE_FILE" images -q "$SERVICE_NAME" 2>/dev/null || echo "")

echo "Pulling latest image..."
docker compose -f "$COMPOSE_FILE" pull

NEW_IMAGE_ID=$(docker compose -f "$COMPOSE_FILE" images -q "$SERVICE_NAME")

if [[ -n "$OLD_IMAGE_ID" && "$OLD_IMAGE_ID" == "$NEW_IMAGE_ID" ]]; then
  echo "Already running the latest image. Nothing to do."
  exit 0
fi

echo "New image detected, updating container..."
docker compose -f "$COMPOSE_FILE" up -d

echo "Waiting for container to be running..."
running=false
for i in $(seq 1 10); do
  if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" == "true" ]]; then
    running=true
    break
  fi
  sleep 2
done

if [[ "$running" != "true" ]]; then
  echo "Container failed to reach running state." >&2
  docker logs "$CONTAINER_NAME" --tail 50 || true
  exit 1
fi

echo "Vaultwarden updated successfully."

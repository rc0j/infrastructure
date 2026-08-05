#!/bin/bash
set -e

COMPOSE_FILE="./docker-compose.yml"
CONTAINER_NAME="vaultwarden"
SERVICE_NAME="vaultwarden"

cd "$(dirname "$0")"

echo "Pulling latest changes from repo..."
git pull origin main

OLD_IMAGE_ID=$(docker inspect -f '{{.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "")

echo "Pulling latest image..."
docker compose -f "$COMPOSE_FILE" pull

NEW_IMAGE_ID=$(docker compose -f "$COMPOSE_FILE" images -q "$SERVICE_NAME")

if [ "$OLD_IMAGE_ID" == "$NEW_IMAGE_ID" ]; then
  echo "Already running the latest image. Nothing to do."
  exit 0
fi

echo "New image detected, updating container..."
docker compose -f "$COMPOSE_FILE" up -d

echo "Waiting for container to be running..."
for i in $(seq 1 10); do
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" == "true" ] && break
  sleep 2
done

if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" != "true" ]; then
  echo "Container failed to reach running state."
  docker logs "$CONTAINER_NAME" --tail 50
  exit 1
fi

echo "Vaultwarden updated successfully."
#!/bin/bash

COMPOSE_FILE="./docker-compose.yml"
CONTAINER_NAME="vaultwarden"

# Step 1: Pull latest changes from the repository
echo "Pulling latest changes from the repository..."
cd "$(dirname "$0")" || exit 1
git pull origin main   # removed 2>/dev/null so real errors are visible if this fails

if [ $? -ne 0 ]; then
  echo "Failed to pull changes from the repository. Aborting deployment."
  exit 1
fi

# Step 3: Stop and remove the existing container
echo "Stopping and removing old container..."
docker compose -f "$COMPOSE_FILE" down
if [ $? -ne 0 ]; then
  echo "Failed to stop existing container. Aborting deployment."
  exit 1
fi

# Step 4: Pull the latest image
echo "Pulling latest image..."
docker compose -f "$COMPOSE_FILE" pull
if [ $? -ne 0 ]; then
  echo "Failed to pull latest image. Aborting deployment."
  exit 1
fi

# Step 5: Start the container
echo "Starting new container..."
docker compose -f "$COMPOSE_FILE" up -d
if [ $? -ne 0 ]; then
  echo "Failed to start container. Aborting deployment."
  exit 1
fi

# Step 6: Wait for the container to report running, instead of a blind sleep
echo "Waiting for container to be up..."
for i in $(seq 1 10); do
  STATE=$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)
  if [ "$STATE" == "true" ]; then
    echo "Container is running."
    break
  fi
  echo "Not running yet, retrying ($i/10)..."
  sleep 2
  if [ "$i" -eq 10 ]; then
    echo "Container failed to reach running state."
    docker logs "$CONTAINER_NAME" --tail 50
    exit 1
  fi
done
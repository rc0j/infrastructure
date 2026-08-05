#!/bin/bash

# Backup script path
BACKUP_SCRIPT="./backup.sh"

# Docker Compose file path
COMPOSE_FILE="./docker-compose.yml"

# Version check URL
VERSION_URL="https://bitwarden.core-forge.fyi"

# Container name (must match docker-compose.yml service/container_name)
CONTAINER_NAME="vaultwarden"

# Step 1: Pull latest changes from the repository
echo "Pulling latest changes from the repository..."
cd "$(dirname "$0")" || exit 1
git pull origin main   # removed 2>/dev/null so real errors are visible if this fails

if [ $? -ne 0 ]; then
  echo "Failed to pull changes from the repository. Aborting deployment."
  exit 1
fi

# Step 2: Run backup script
echo "Running backup script..."
if [ -x "$BACKUP_SCRIPT" ]; then
  "$BACKUP_SCRIPT"
  if [ $? -ne 0 ]; then
    echo "Backup failed. Aborting deployment."
    exit 1
  fi
elif [ -f "$BACKUP_SCRIPT" ]; then
  echo "Backup script found but not executable. Run: chmod +x $BACKUP_SCRIPT"
  exit 1
else
  echo "Backup script not found at $BACKUP_SCRIPT. We cannot continue"
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

# Fix permissions on data dir before starting (only if it exists)
if [ -d "./vw-data" ]; then
  echo "Fixing permissions on vw-data..."
  chown vaultwarden:vaultwarden -R ./vw-data
else
  echo "./vw-data not found, skipping permission fix (expected on first run)."
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

# Step 7: Confirm the app is actually responding, not just the container process
echo "Checking Vaultwarden version..."
VERSION=""
for i in $(seq 1 10); do
  VERSION=$(curl -s "$VERSION_URL" | grep -oiP '(?<=Vaultwarden Web )[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
  if [[ -n "$VERSION" ]]; then
    break
  fi
  echo "App not responding yet, retrying ($i/10)..."
  sleep 2
done

if [[ -z "$VERSION" ]]; then
  echo "Failed to retrieve version from homepage. Check if the server is running."
  docker logs "$CONTAINER_NAME" --tail 50
  exit 1
fi

echo "Vaultwarden updated successfully - running version $VERSION"
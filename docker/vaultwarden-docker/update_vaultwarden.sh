#!/bin/bash

# Backup script path
BACKUP_SCRIPT="/home/vaultwarden/vaultwarden-docker/backup.sh"

# Docker Compose file path
COMPOSE_FILE="docker/vaultwarden-docker/docker-compose.yml"

# Version check URL
VERSION_URL="https://bitwarden.core-forge.fyi"

# Step 1: Pull latest changes from the repository
echo "Pulling latest changes from the repository..."
cd "$(dirname "$0")" || exit
git pull origin main 2>/dev/null

if [ $? -ne 0 ]; then
  echo "❌ Failed to pull changes from the repository. Aborting deployment."
  exit 1
fi

# Step 2: Run backup script
# temporariy disable backup
# echo "Running backup script..."
# if [ -f "$BACKUP_SCRIPT" ]; then
#   $BACKUP_SCRIPT
#   if [ $? -ne 0 ]; then
#     echo "Backup failed. Aborting deployment."
#     exit 1
#   fi
# else
#   echo "Backup script not found at $BACKUP_SCRIPT. We cannot continue"
#   exit 1
# fi

# Step 3: Stop and remove the existing container
echo "Stopping and removing old container..."
docker compose -f "$COMPOSE_FILE" down

# Step 4: Pull the latest image
echo "Pulling latest image..."
docker compose -f "$COMPOSE_FILE" pull

# Step 5: Start the container
echo "Starting new container..."
docker compose -f "$COMPOSE_FILE" up -d

# Step 6: Check the version from the homepage
echo "Checking Vaultwarden version..."
VERSION_REGEX="Vaultwarden Web ([0-9]+\.[0-9]+\.[0-9]+)"
VERSION=$(curl -s "$VERSION_URL" | grep -oP "$VERSION_REGEX" | head -n 1)

if [[ -z "$VERSION" ]]; then
  echo "Failed to retrieve version from homepage. Check if the server is running."
  docker compose -f "$COMPOSE_FILE" logs vaultwarden
  exit 1
fi

# Step 8: Success message
echo "Vaultwarden updated successfully. Version: $VERSION"

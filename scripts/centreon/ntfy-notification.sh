#!/bin/bash

source ./ntfy-notification.env

set -euo pipefail

# Variables passed from Centreon
TITLE="$1"
MESSAGE="$2"
PRIORITY="$3" # e.g., high, default, low

curl -H "Title: $TITLE" \
     -H "Priority: $PRIORITY" \
     -d "$MESSAGE" \
     $NTFY_URL
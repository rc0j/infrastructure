#!/bin/bash
set -euo pipefail

source ./ntfy-notification.env

# Variables passed from Centreon (map these to macros in the command definition)
HOST="$1"          # $HOSTNAME$
SERVICE="$2"       # $SERVICEDESC$ (or "N/A" for host alerts)
STATE="$3"         # $SERVICESTATE$ / $HOSTSTATE$ (OK, WARNING, CRITICAL, UNKNOWN, DOWN, UP)
OUTPUT="$4"        # $SERVICEOUTPUT$ / $HOSTOUTPUT$
DATE="$5"          # $DATE$ $TIME$

# Map Centreon state to ntfy priority
case "$STATE" in
    CRITICAL|DOWN)  PRIORITY="urgent" ;;
    WARNING)        PRIORITY="high" ;;
    UNKNOWN)        PRIORITY="default" ;;
    OK|UP)          PRIORITY="low" ;;
    *)              PRIORITY="default" ;;
esac

TITLE="[$STATE] $HOST/$SERVICE"

MESSAGE="Host: $HOST
Service: $SERVICE
State: $STATE
Time: $DATE

$OUTPUT"

RESPONSE=$(curl -sS -w "\nHTTP_CODE:%{http_code}" \
     -H "Title: $TITLE" \
     -H "Priority: $PRIORITY" \
     -d "$MESSAGE" \
     "$NTFY_URL")

HTTP_CODE=$(echo "$RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '$d')

echo "ntfy response: $BODY"
echo "HTTP status: $HTTP_CODE"

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    echo "ERROR: ntfy notification failed" >&2
    exit 1
fi

echo "Notification sent successfully"
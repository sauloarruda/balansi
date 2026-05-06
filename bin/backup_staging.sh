#!/bin/bash

# Script to backup the SQLite database from staging on Fly.io
# Saves the backup in the local storage/ folder

set -e  # Stop the script if there's an error

APP_NAME="balansi-staging"
# Get the machine ID dynamically
MACHINE_ID=$(flyctl machines list -a "$APP_NAME" --json | jq -r '.[0].id')
REMOTE_DB_PATH="/rails/storage/staging.sqlite3"
LOCAL_BACKUP_DIR="./storage"
BACKUP_FILENAME="staging_backup_$(date +%Y%m%d_%H%M%S).sqlite3"

echo "🚀 Starting staging database backup..."
echo "📱 Starting Fly.io machine..."

# Start the machine
flyctl machine start "$MACHINE_ID" -a "$APP_NAME"

echo "✅ Machine started successfully!"
echo "🔧 Installing sqlite3 in the container..."

# Install sqlite3 and perform backup
flyctl ssh console -a "$APP_NAME" -C "bash -lc \"apt-get update -qq && apt-get install --no-install-recommends -y sqlite3 && echo 'SQLite installed!'\""

echo "💾 Creating database backup..."

# Create consistent backup
flyctl ssh console -a "$APP_NAME" -C "bash -lc \"sqlite3 $REMOTE_DB_PATH '.backup /tmp/$BACKUP_FILENAME' && echo 'Backup created at /tmp/$BACKUP_FILENAME'\""

echo "⬇️ Downloading backup to local folder..."

# Download the file
flyctl ssh sftp get "/tmp/$BACKUP_FILENAME" "$LOCAL_BACKUP_DIR/$BACKUP_FILENAME" -a "$APP_NAME"

echo "🎉 Backup completed successfully!"
echo "📁 File saved at: $LOCAL_BACKUP_DIR/$BACKUP_FILENAME"
echo "📊 Backup size: $(du -h "$LOCAL_BACKUP_DIR/$BACKUP_FILENAME" | cut -f1)"

echo ""
echo "💡 Tip: To restore, copy the file to /rails/storage/staging.sqlite3 in the container"
echo "   and restart the application."
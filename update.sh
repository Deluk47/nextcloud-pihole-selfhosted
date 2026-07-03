#!/usr/bin/env bash
set -e

echo "Updating Pi-hole stack..."
cd "$(dirname "$0")"

echo "Pulling latest changes from Git..."
git pull origin main

echo "Pulling latest images..."
docker compose pull

echo "Restarting Pi-hole stack..."
docker compose up -d

echo "Update complete."

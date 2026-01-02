#!/bin/bash

echo "🛑 Stopping VN Party Development Environment..."

# Stop Docker containers
docker-compose down

echo "✅ Environment stopped!"

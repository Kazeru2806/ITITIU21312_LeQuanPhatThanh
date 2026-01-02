#!/bin/bash

echo "🚀 Starting VN Party Development Environment..."

# Start databases
echo "📦 Starting Docker containers..."
docker-compose up -d

# Wait for databases to be ready
echo "⏳ Waiting for databases..."
sleep 5

# Function to start services in new terminal tabs
start_service() {
    osascript -e "tell application \"Terminal\" to do script \"cd '$1' && $2\""
}

# Start backend
echo "🔧 Starting Phoenix backend..."
start_service "/Users/kazeru2806/Documents/Github/vn-party-thesis/backend" "mix phx.server"

# Wait a bit
sleep 2

# Start player client
echo "🎮 Starting Player Client..."
start_service "/Users/kazeru2806/Documents/Github/vn-party-thesis/frontend-player" "npm run dev"

# Start host client
echo "📺 Starting Host Client..."
start_service "/Users/kazeru2806/Documents/Github/vn-party-thesis/frontend-host" "npm run dev"

echo "✅ Development environment started!"
echo ""
echo "Access points:"
echo "  Backend:  http://localhost:4000"
echo "  Player:   http://localhost:5173"
echo "  Host:     http://localhost:5174"

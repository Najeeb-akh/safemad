#!/bin/bash

# Start the SafeMad backend server
# This script helps ensure the server starts correctly

cd "$(dirname "$0")"

echo "🚀 Starting SafeMad Backend Server..."
echo "📍 Working directory: $(pwd)"
echo ""

# Check if port 8000 is already in use
if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "⚠️  Port 8000 is already in use!"
    echo "   Please stop the existing server first or use a different port."
    exit 1
fi

# Start the server
echo "Starting uvicorn server..."
python3 -m uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000

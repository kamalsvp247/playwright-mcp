#!/bin/bash
set -e

export DISPLAY=:99

# Start a persistent virtual display for headed Playwright sessions.
Xvfb "$DISPLAY" -screen 0 1280x1024x24 >/tmp/xvfb.log 2>&1 &

# Give Xvfb a moment to initialize.
sleep 3

# Expose the display over VNC.
x11vnc -display "$DISPLAY" -forever -shared -nopw -rfbport 5900 -bg -o /var/log/x11vnc.log >/tmp/x11vnc.log 2>&1 || true

# Bridge VNC to a browser-accessible noVNC web client on port 6080.
websockify --web=/usr/share/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 &

echo "noVNC viewer available on port 6080"
echo "Next.js app will start on port ${PORT:-8080}"

# Keep the container alive and bind the app to all interfaces.
exec npm run start -- --hostname 0.0.0.0 --port "${PORT:-8080}"

#!/bin/bash

export DISPLAY=:99

Xvfb "$DISPLAY" -screen 0 1280x1024x24 >/tmp/xvfb.log 2>&1 &

sleep 3

x11vnc -display "$DISPLAY" -forever -shared -nopw -rfbport 5900 -bg -o /var/log/x11vnc.log >/tmp/x11vnc.log 2>&1 || true

websockify --web=/usr/share/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 &

echo "noVNC viewer available on port 6080"
echo "Next.js app will start on port ${PORT:-8080}"

exec npm run start -- --hostname 0.0.0.0 --port "${PORT:-8080}"

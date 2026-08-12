FROM node:22-bookworm

WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    PORT=8080 \
    HOSTNAME=0.0.0.0

COPY package*.json ./
# NODE_ENV=production is already set above, so npm would omit devDependencies
# (including @tailwindcss/postcss, needed by the Next.js/Turbopack build).
# --include=dev installs everything so `npm run build` succeeds.
RUN npm ci --include=dev

# Install full Chromium (not --only-shell) plus its system deps.
RUN npx playwright install --with-deps chromium

# Persistent virtual display + remote viewing: xauth (X auth cookies),
# x11vnc (exposes the display over VNC), websockify+novnc (VNC-over-HTTP
# so it is viewable in a plain browser tab, no VNC client needed).
RUN apt-get update && apt-get install -y --no-install-recommends \
    xauth x11vnc novnc websockify xvfb dbus-x11 \
    && rm -rf /var/lib/apt/lists/*

COPY . .
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN npm run build

# 8080 = app, 6080 = noVNC web viewer (watch/control the login browser)
EXPOSE 8080 6080

CMD ["sh", "/entrypoint.sh"]

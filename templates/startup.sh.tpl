#!/bin/bash
set -euo pipefail

exec > >(tee -a /var/log/startup-script.log) 2>&1
echo "=== EspoCRM startup script started at $(date -u) ==="

# -----------------------------------------------------------------------------
# 1. Install Docker (idempotent)
# -----------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
  systemctl start docker
  echo "Docker installed successfully."
else
  echo "Docker already installed, skipping."
fi

# Verify Docker Compose plugin is available
if ! docker compose version &>/dev/null; then
  echo "ERROR: Docker Compose plugin not found after installation."
  exit 1
fi

echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"

# -----------------------------------------------------------------------------
# 2. Fetch secrets from Secret Manager
# -----------------------------------------------------------------------------
echo "Fetching secrets from Secret Manager..."

DB_PASSWORD=$(gcloud secrets versions access latest \
  --secret=espocrm-db-password \
  --project=${project_id})

ADMIN_PASSWORD=$(gcloud secrets versions access latest \
  --secret=espocrm-admin-password \
  --project=${project_id})

# OAuth client secret may not exist yet (created after manual OAuth setup)
OAUTH_CLIENT_SECRET=""
if gcloud secrets versions access latest \
  --secret=espocrm-oauth-client-secret \
  --project=${project_id} &>/dev/null; then
  OAUTH_CLIENT_SECRET=$(gcloud secrets versions access latest \
    --secret=espocrm-oauth-client-secret \
    --project=${project_id})
  echo "OAuth client secret fetched."
else
  echo "OAuth client secret not found or has no versions, skipping."
fi

echo "Secrets fetched successfully."

# -----------------------------------------------------------------------------
# 3. Write configuration files
# -----------------------------------------------------------------------------
echo "Writing configuration files to /opt/espocrm/..."
mkdir -p /opt/espocrm

# --- GCP credentials for AI Backend -----------------------------------------
# Create a service account key for the AI Backend container to authenticate
# with Vertex AI (Gemini). The container runs on a Docker bridge network and
# cannot reach the GCE metadata server, so it needs an explicit key file.
GCP_CREDS_PATH="/opt/espocrm/gcp-credentials.json"
if [ ! -f "$GCP_CREDS_PATH" ]; then
  echo "Creating GCP service account key for AI Backend..."
  SA_EMAIL=$(curl -s -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email)
  gcloud iam service-accounts keys create "$GCP_CREDS_PATH" \
    --iam-account="$SA_EMAIL" \
    --project="${project_id}" 2>/dev/null || {
    echo "WARNING: Could not create service account key. AI Backend may not authenticate with Vertex AI."
    echo "Ensure the service account has the iam.serviceAccountKeys.create permission."
    echo '{}' > "$GCP_CREDS_PATH"
  }
  # Make readable by non-root container users (ai-backend runs as appuser)
  chmod 644 "$GCP_CREDS_PATH"
  echo "GCP credentials file written."
else
  echo "GCP credentials file already exists, skipping."
fi

# --- docker-compose.yml -----------------------------------------------------
# Terraform template variables (db_host, db_name, etc.) are substituted at
# plan time. Shell variables (DB_PASSWORD, ADMIN_PASSWORD, OAUTH_CLIENT_SECRET)
# are expanded at runtime by the heredoc.
cat > /opt/espocrm/docker-compose.yml <<COMPOSE
services:
  caddy:
    image: caddy:2
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy-data:/data
      - caddy-config:/config

  espocrm:
    image: espocrm/espocrm:9.3.4
    restart: always
    expose:
      - "80"
    environment:
      ESPOCRM_DATABASE_PLATFORM: Mysql
      ESPOCRM_DATABASE_HOST: "${db_host}"
      ESPOCRM_DATABASE_NAME: "${db_name}"
      ESPOCRM_DATABASE_USER: "${db_user}"
      ESPOCRM_DATABASE_PASSWORD: "$${DB_PASSWORD}"
      ESPOCRM_ADMIN_USERNAME: admin
      ESPOCRM_ADMIN_PASSWORD: "$${ADMIN_PASSWORD}"
      ESPOCRM_SITE_URL: "https://${domain}"
      ESPOCRM_CONFIG_AUTH_AUTHENTICATION_METHOD: "${oauth_client_id != "" ? "Oidc" : ""}"
      ESPOCRM_CONFIG_OIDC_CLIENT_ID: "${oauth_client_id}"
      ESPOCRM_CONFIG_OIDC_CLIENT_SECRET: "$${OAUTH_CLIENT_SECRET}"
      ESPOCRM_CONFIG_OIDC_AUTHORIZATION_REDIRECT_URI: "https://${domain}"
      ESPOCRM_CONFIG_OIDC_USERNAME_CLAIM: email
      ESPOCRM_CONFIG_OIDC_CREATE_USER: "true"
      ESPOCRM_CONFIG_OIDC_FALLBACK: "true"
    volumes:
      - espocrm-data:/var/www/html

  espocrm-daemon:
    image: espocrm/espocrm:9.3.4
    restart: always
    entrypoint: docker-daemon.sh
    volumes:
      - espocrm-data:/var/www/html

  espocrm-websocket:
    image: espocrm/espocrm:9.3.4
    restart: always
    entrypoint: docker-websocket.sh
    expose:
      - "8080"
    environment:
      ESPOCRM_CONFIG_USE_WEB_SOCKET: "true"
      ESPOCRM_CONFIG_WEB_SOCKET_URL: "wss://${domain}/ws"
      ESPOCRM_CONFIG_WEB_SOCKET_ZERO_M_Q_SUBSCRIBER_DSN: "tcp://*:7777"
      ESPOCRM_CONFIG_WEB_SOCKET_ZERO_M_Q_SUBMISSION_DSN: "tcp://espocrm-websocket:7777"
    volumes:
      - espocrm-data:/var/www/html

  ai-backend:
    build:
      context: ./ai-backend
      dockerfile: Dockerfile
    container_name: ai-backend
    restart: always
    ports:
      - "127.0.0.1:3001:3001"
    environment:
      NODE_ENV: production
      PORT: "3001"
      ESPOCRM_URL: "http://espocrm:80"
      GOOGLE_CLOUD_PROJECT: "${project_id}"
      GOOGLE_CLOUD_REGION: "${region}"
      GOOGLE_APPLICATION_CREDENTIALS: /app/credentials.json
      GEMINI_DEFAULT_MODEL: gemini-3-flash-preview
      GEMINI_AVAILABLE_MODELS: gemini-3-flash-preview,gemini-3.1-pro-preview,gemini-3.1-flash-lite-preview
      SESSION_TIMEOUT_MS: "1800000"
      RATE_LIMIT_PER_MIN: "30"
      MAX_CONTEXT_MESSAGES: "20"
      LOG_LEVEL: info
    volumes:
      - /tmp/ai-backend-uploads:/tmp/uploads
      - /opt/espocrm/gcp-credentials.json:/app/credentials.json:ro
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s

volumes:
  espocrm-data:
  caddy-data:
  caddy-config:
COMPOSE

echo "docker-compose.yml written."

# --- Caddyfile ---------------------------------------------------------------
# Caddy placeholders {host}, {remote}, {scheme} are safe — Terraform only
# interpolates dollar-brace and percent-brace syntax, not bare {braces}.
cat > /opt/espocrm/Caddyfile <<CADDY
${domain} {
    handle /ai-api/* {
        reverse_proxy ai-backend:3001
    }

    reverse_proxy espocrm:80

    reverse_proxy /ws espocrm-websocket:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
    }
}
CADDY

echo "Caddyfile written."

# -----------------------------------------------------------------------------
# 4. Test database connectivity (5 attempts, 10-second intervals)
# -----------------------------------------------------------------------------
echo "Testing database connectivity to ${db_host}..."

MAX_RETRIES=5
RETRY_INTERVAL=10

for i in $(seq 1 $MAX_RETRIES); do
  echo "Attempt $i/$MAX_RETRIES: pinging ${db_host}..."
  if docker run --rm --network host mysql:8 \
    mysqladmin ping \
    -h "${db_host}" \
    -u "${db_user}" \
    -p"$DB_PASSWORD" \
    --silent 2>/dev/null; then
    echo "Database is reachable."
    break
  fi

  if [ "$i" -eq "$MAX_RETRIES" ]; then
    echo "ERROR: Database not reachable after $MAX_RETRIES attempts. Aborting."
    exit 1
  fi

  echo "Database not ready, retrying in $${RETRY_INTERVAL}s..."
  sleep $RETRY_INTERVAL
done

# -----------------------------------------------------------------------------
# 5. Clone AI Backend source code for Docker build
# -----------------------------------------------------------------------------
echo "Setting up AI Backend source code..."
AI_BACKEND_DIR="/opt/espocrm/ai-backend"
if [ ! -d "$AI_BACKEND_DIR/src" ]; then
  echo "Cloning repository for AI Backend source..."
  apt-get install -y git 2>/dev/null || true
  TEMP_REPO=$(mktemp -d)
  git clone --depth 1 https://github.com/JuntoAI/espocrm-ai-backend.git "$TEMP_REPO" 2>/dev/null || {
    echo "WARNING: Could not clone repo. AI Backend will not be available."
    echo "You can manually copy ai-backend/ to $AI_BACKEND_DIR"
  }
  if [ -d "$TEMP_REPO/ai-backend" ]; then
    mkdir -p "$AI_BACKEND_DIR"
    cp -r "$TEMP_REPO/ai-backend/"* "$AI_BACKEND_DIR/"
    # Copy MCP server source for bundling into the Docker image
    if [ -d "$TEMP_REPO/EspoMCP/EspoMCP" ]; then
      mkdir -p "$AI_BACKEND_DIR/mcp-server"
      cp "$TEMP_REPO/EspoMCP/EspoMCP/package.json" "$AI_BACKEND_DIR/mcp-server/"
      cp "$TEMP_REPO/EspoMCP/EspoMCP/package-lock.json" "$AI_BACKEND_DIR/mcp-server/" 2>/dev/null || true
      cp "$TEMP_REPO/EspoMCP/EspoMCP/tsconfig.json" "$AI_BACKEND_DIR/mcp-server/"
      cp -r "$TEMP_REPO/EspoMCP/EspoMCP/src" "$AI_BACKEND_DIR/mcp-server/src"
      echo "MCP server source copied for bundling."
    fi
    echo "AI Backend source ready."
  fi
  rm -rf "$TEMP_REPO"
else
  echo "AI Backend source already exists, skipping."
fi

# Create uploads directory
mkdir -p /tmp/ai-backend-uploads

# -----------------------------------------------------------------------------
# 6. Start the Docker Compose stack
# -----------------------------------------------------------------------------
echo "Starting Docker Compose stack..."
docker compose -f /opt/espocrm/docker-compose.yml up -d

echo "=== EspoCRM startup script completed at $(date -u) ==="

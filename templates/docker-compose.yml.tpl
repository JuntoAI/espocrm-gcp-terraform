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
      ESPOCRM_DATABASE_HOST: ${db_host}
      ESPOCRM_DATABASE_NAME: ${db_name}
      ESPOCRM_DATABASE_USER: ${db_user}
      ESPOCRM_DATABASE_PASSWORD: ${db_password}
      ESPOCRM_ADMIN_USERNAME: admin
      ESPOCRM_ADMIN_PASSWORD: ${admin_password}
      ESPOCRM_SITE_URL: https://${domain}
      ESPOCRM_CONFIG_AUTH_AUTHENTICATION_METHOD: ${oauth_client_id != "" ? "Oidc" : ""}
      ESPOCRM_CONFIG_OIDC_CLIENT_ID: ${oauth_client_id}
      ESPOCRM_CONFIG_OIDC_AUTHORIZATION_REDIRECT_URI: https://${domain}
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
      ESPOCRM_CONFIG_WEB_SOCKET_URL: wss://${domain}/ws
      ESPOCRM_CONFIG_WEB_SOCKET_ZERO_M_Q_SUBSCRIBER_DSN: tcp://*:7777
      ESPOCRM_CONFIG_WEB_SOCKET_ZERO_M_Q_SUBMISSION_DSN: tcp://espocrm-websocket:7777
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
      ESPOCRM_URL: http://espocrm:80
      GOOGLE_CLOUD_PROJECT: ${project_id}
      GOOGLE_CLOUD_REGION: ${region}
      GOOGLE_APPLICATION_CREDENTIALS: /app/credentials.json
      GEMINI_DEFAULT_MODEL: gemini-3.5-flash
      GEMINI_AVAILABLE_MODELS: gemini-3.5-flash,gemini-3-flash-preview,gemini-3.1-pro-preview,gemini-3.1-flash-lite-preview
      SESSION_TIMEOUT_MS: "1800000"
      RATE_LIMIT_PER_MIN: "30"
      MAX_CONTEXT_MESSAGES: "20"
      LOG_LEVEL: info
      USER_CONFIG_PATH: /data/user-configs
    volumes:
      - /tmp/ai-backend-uploads:/tmp/uploads
      - /opt/espocrm/user-configs:/data/user-configs
      - ${gcp_credentials_path:-/opt/espocrm/gcp-credentials.json}:/app/credentials.json:ro
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

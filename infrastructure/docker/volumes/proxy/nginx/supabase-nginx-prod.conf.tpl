# ============================================================
# License Forge — Production Outer nginx
# Three vhosts: app.${PROXY_DOMAIN}, api.${PROXY_DOMAIN}, studio.${PROXY_DOMAIN}
# Rendered from this template at container start by envsubst.
# ============================================================

# ---- Rate-limit zones ----
limit_req_zone $binary_remote_addr zone=api_general:10m rate=20r/s;
limit_req_zone $binary_remote_addr zone=api_auth:10m    rate=5r/s;
limit_req_zone $binary_remote_addr zone=studio:10m      rate=5r/s;

# ---- TLS hardening ----
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers off;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;

# Optional Diffie-Hellman params (jonasal/nginx-certbot generates dhparams automatically)
ssl_dhparam /etc/letsencrypt/dhparams/dhparam.pem;

# Hide nginx version
server_tokens off;

# Buffers — Supabase auth cookies can be large (carried over from prior nginx config)
large_client_header_buffers 4 16k;
proxy_buffer_size 128k;
proxy_buffers 4 256k;
proxy_busy_buffers_size 256k;

# HSTS header value (mapped so we can apply it consistently)
map $sent_http_content_type $hsts_header {
    default "max-age=63072000; includeSubDomains; preload";
}

# ============================================================
# app.${PROXY_DOMAIN} — frontend SPA
# ============================================================
server {
    listen 80;
    listen [::]:80;
    server_name app.${PROXY_DOMAIN};

    # Allow ACME HTTP-01 challenge (jonasal-managed); redirect everything else
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name app.${PROXY_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/app.${PROXY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.${PROXY_DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/app.${PROXY_DOMAIN}/chain.pem;

    add_header Strict-Transport-Security $hsts_header always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self' https://api.${PROXY_DOMAIN} wss://api.${PROXY_DOMAIN}; frame-ancestors 'none'; base-uri 'self'; form-action 'self'" always;

    location / {
        proxy_pass http://web:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

# ============================================================
# api.${PROXY_DOMAIN} — Kong → Supabase services
# ============================================================
server {
    listen 80;
    listen [::]:80;
    server_name api.${PROXY_DOMAIN};

    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name api.${PROXY_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/api.${PROXY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.${PROXY_DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/api.${PROXY_DOMAIN}/chain.pem;

    add_header Strict-Transport-Security $hsts_header always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;

    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host $http_host;
    proxy_set_header X-Forwarded-Port $server_port;

    # Auth flow endpoints — strict rate limit (signup / login / password reset / OTP)
    location ~ ^/auth/v1/(token|signup|recover|otp|magiclink) {
        limit_req zone=api_auth burst=10 nodelay;
        proxy_pass http://kong:8000;
    }

    # Realtime — WebSocket upgrade + long timeout
    # NOTE: nginx drops inherited proxy_set_header directives when ANY proxy_set_header
    # is defined at this level, so we must re-declare the standard six here.
    location /realtime/v1/ {
        proxy_pass http://kong:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }

    # Storage uploads — disable buffering, allow large bodies
    location /storage/v1/ {
        proxy_pass http://kong:8000;
        proxy_buffering off;
        proxy_request_buffering off;
        chunked_transfer_encoding off;
        client_max_body_size 0;
    }

    # General API — moderate rate limit, 50M body cap
    location / {
        limit_req zone=api_general burst=40 nodelay;
        client_max_body_size 50M;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
        proxy_pass http://kong:8000;
    }
}

# ============================================================
# studio.${PROXY_DOMAIN} — Studio dashboard (IP allowlist + basic auth)
# ============================================================
server {
    listen 80;
    listen [::]:80;
    server_name studio.${PROXY_DOMAIN};

    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name studio.${PROXY_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/studio.${PROXY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/studio.${PROXY_DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/studio.${PROXY_DOMAIN}/chain.pem;

    add_header Strict-Transport-Security $hsts_header always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;

    # IP allowlist — studio-allowlist.conf is generated at container start
    # from STUDIO_ALLOWED_CIDRS (empty = empty file = `deny all` matches all = 403)
    include /etc/nginx/user_conf.d/studio-allowlist.conf;
    deny all;

    # Then basic auth on top of IP allowlist
    auth_basic           "License Forge Studio";
    auth_basic_user_file /etc/nginx/user_conf.d/dashboard-passwd;

    limit_req zone=studio burst=10 nodelay;

    location / {
        proxy_pass http://studio:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

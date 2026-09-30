#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/var/www/devops-portfolio"
NGINX_SITE="/etc/nginx/sites-available/devops-portfolio"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo: sudo bash scripts/bootstrap-ec2.sh" >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx ec2-instance-connect curl ca-certificates

mkdir -p "$APP_ROOT/releases"
chown -R ubuntu:www-data "$APP_ROOT"
chmod 2755 "$APP_ROOT" "$APP_ROOT/releases"

cat > "$NGINX_SITE" <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;
    server_tokens off;

    root /var/www/devops-portfolio/current;
    index index.html;

    location = /health {
        access_log off;
        default_type text/plain;
        return 200 "ok\n";
    }

    location / {
        try_files $uri $uri/ =404;
    }

    location ~* \.(?:css|js|mjs|jpg|jpeg|png|gif|ico|svg|webp|woff|woff2|ttf)$ {
        try_files $uri =404;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000";
    }

    location ~* \.pdf$ {
        try_files $uri =404;
        expires 1h;
        add_header Cache-Control "public, max-age=3600";
        add_header Content-Disposition "inline";
    }

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

    client_max_body_size 1m;
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sfn "$NGINX_SITE" /etc/nginx/sites-enabled/devops-portfolio

nginx -t
systemctl enable nginx
systemctl restart nginx

echo
printf 'EC2 bootstrap complete.\n'
printf 'Nginx: %s\n' "$(nginx -v 2>&1)"
printf 'App root: %s\n' "$APP_ROOT"
printf 'The first GitHub Actions deployment will create the current release symlink.\n'

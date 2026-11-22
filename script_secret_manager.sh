#!/bin/bash
set -euo pipefail

SECRET="laravel_db_password"
PROJECT="belajar-project-terraform"
BUCKET="belajar-project-terraform-laravel"
ENV_FILE="/var/www/school-app/.env"  
SQL_PROXY_FILE="/etc/systemd/system/cloud-sql-proxy.service"
CONNECTION_NAME="belajar-project-terraform:asia-southeast2:laravel-sql-instance"
PASSWORD=$(gcloud secrets versions access latest --secret="$SECRET" --project="$PROJECT")
USERNAME="laravel"

sed -i \
-e "s~^[[:space:]]*DB_PASSWORD=.*~DB_PASSWORD=${PASSWORD}~" \
-e "s~^[[:space:]]*DB_USERNAME=.*~DB_USERNAME=${USERNAME}~" \
-e "s~^[[:space:]]*GOOGLE_CLOUD_PROJECT_ID=.*~GOOGLE_CLOUD_PROJECT_ID=${PROJECT}~" \
-e "s~^[[:space:]]*GOOGLE_CLOUD_STORAGE_BUCKET=.*~GOOGLE_CLOUD_STORAGE_BUCKET=${BUCKET}~" \
"$ENV_FILE"

sed -i "s~^ExecStart=/usr/local/bin/cloud-sql-proxy.*~ExecStart=/usr/local/bin/cloud-sql-proxy --private-ip ${CONNECTION_NAME} --port=5432~" "$SQL_PROXY_FILE"

cd /var/www/school-app
php artisan config:clear
systemctl daemon-reload
systemctl restart cloud-sql-proxy
systemctl restart apache2

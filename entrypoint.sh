#!/bin/bash
set -e

PROJECT_TYPE="${PROJECT_TYPE:-generic}"
WEB_SERVER="${WEB_SERVER:-nginx}"
HTTP_PORT="${HTTP_PORT:-80}"

log() { echo "[devenv] $*"; }

# ── 0. Wait for MySQL if needed ─────────────────────────────────────
if [ "$PROJECT_TYPE" = "wordpress" ] || [ "$PROJECT_TYPE" = "laravel" ]; then
    log "Waiting for MySQL at ${DB_HOST:-host.docker.internal}:${DB_PORT:-3306}..."
    for i in $(seq 1 30); do
        if php -r "new PDO('mysql:host=${DB_HOST:-host.docker.internal};port=${DB_PORT:-3306}', '${DB_USER:-root}', '${DB_PASSWORD:-}');" 2>/dev/null; then
            log "MySQL is ready."
            break
        fi
        if [ "$i" -eq 30 ]; then
            log "WARNING: MySQL not reachable after 30s. Continuing anyway..."
        fi
        sleep 1
    done
fi

# ── 1. WordPress: download core on first run ────────────────────────
if [ "$PROJECT_TYPE" = "wordpress" ] && [ ! -f /var/www/html/.devenv-installed ]; then
    log "Downloading WordPress ${WP_VERSION:-latest}..."
    wp core download \
        --version="${WP_VERSION:-latest}" \
        --path=/var/www/html \
        --allow-root

    log "Configuring WordPress..."
    wp config create \
        --path=/var/www/html \
        --dbname="${DB_NAME:-wordpress}" \
        --dbuser="${DB_USER:-root}" \
        --dbpass="${DB_PASSWORD:-}" \
        --dbhost="${DB_HOST:-host.docker.internal}:${DB_PORT:-3306}" \
        --allow-root \
        --extra-php <<'EXTRA_PHP'
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', true);
define('SCRIPT_DEBUG', true);
define('FS_METHOD', 'direct');
define('WP_MEMORY_LIMIT', '256M');
EXTRA_PHP

    log "Installing WordPress..."
    wp core install \
        --path=/var/www/html \
        --url="http://localhost:${HTTP_PORT}" \
        --title="${COMPOSE_PROJECT_NAME:-Dev}" \
        --admin_user=admin \
        --admin_password=admin \
        --admin_email=dev@local.test \
        --skip-email \
        --allow-root

    if [ -n "$PLUGIN_SLUG" ]; then
        log "Activating plugin: ${PLUGIN_SLUG}"
        wp plugin activate "$PLUGIN_SLUG" --allow-root --path=/var/www/html || true
    fi

    echo "${WP_VERSION:-latest}" > /var/www/html/.wp-version
    touch /var/www/html/.devenv-installed
    log "WordPress ready."
fi

# Check for WP version mismatch
if [ "$PROJECT_TYPE" = "wordpress" ] && [ -f /var/www/html/.devenv-installed ]; then
    INSTALLED_VER=$(cat /var/www/html/.wp-version 2>/dev/null || echo "unknown")
    REQUESTED_VER="${WP_VERSION:-latest}"
    if [ "$INSTALLED_VER" != "$REQUESTED_VER" ] && [ "$REQUESTED_VER" != "latest" ]; then
        log "NOTE: WP version mismatch — installed=${INSTALLED_VER}, requested=${REQUESTED_VER}"
        log "Run 'dev clean && dev up' to reinstall, or 'dev wp core update --version=${REQUESTED_VER}' to upgrade in-place."
    fi
fi

# ── 2. Laravel: composer install if vendor missing ──────────────────
if [ "$PROJECT_TYPE" = "laravel" ] && [ ! -f /var/www/html/vendor/autoload.php ]; then
    if [ -f /var/www/html/composer.json ]; then
        log "Running composer install..."
        cd /var/www/html
        COMPOSER_CACHE_DIR=/home/www-data/.composer/cache composer install --no-interaction --prefer-dist --optimize-autoloader
        log "Composer install complete."
    else
        log "No composer.json found — skipping composer install."
    fi
fi

# ── 3. Fix ownership (only on first run — skip recursive chown on warm starts) ──
if [ ! -f /var/www/html/.chown-done ]; then
    log "Setting file ownership..."
    chown -R www-data:www-data /var/www/html 2>/dev/null || true
    touch /var/www/html/.chown-done
else
    # Only fix top-level on warm starts
    chown www-data:www-data /var/www/html 2>/dev/null || true
fi

# ── 4. Create healthcheck endpoint ──────────────────────────────────
echo '<?php http_response_code(200); echo "ok";' > /var/www/html/_health.php
chown www-data:www-data /var/www/html/_health.php 2>/dev/null || true

# ── 5. Start PHP-FPM (background) ──────────────────────────────────
log "Starting PHP-FPM..."
php-fpm -D

# ── 6. Start web server (foreground) ───────────────────────────────
if [ "$WEB_SERVER" = "nginx" ]; then
    log "Starting nginx on port 80..."
    exec nginx -g "daemon off;"
elif [ "$WEB_SERVER" = "apache" ]; then
    log "Starting Apache on port 80..."
    exec httpd -D FOREGROUND
else
    log "Unknown WEB_SERVER: ${WEB_SERVER}. Falling back to nginx."
    exec nginx -g "daemon off;"
fi

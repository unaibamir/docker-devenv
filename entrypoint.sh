#!/bin/bash
set -e

PROJECT_TYPE="${PROJECT_TYPE:-generic}"
WEB_SERVER="${WEB_SERVER:-nginx}"
HTTP_PORT="${HTTP_PORT:-80}"

log() { echo "[devenv] $*"; }

# ── 1. WordPress: download core on first run ────────────────────────
if [ "$PROJECT_TYPE" = "wordpress" ] && [ ! -f /var/www/html/wp-load.php ]; then
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

    log "WordPress ready."
fi

# ── 2. Laravel: composer install if vendor missing ──────────────────
if [ "$PROJECT_TYPE" = "laravel" ] && [ ! -f /var/www/html/vendor/autoload.php ]; then
    log "Running composer install..."
    cd /var/www/html
    composer install --no-interaction --prefer-dist --optimize-autoloader
    log "Composer install complete."
fi

# ── 3. Fix ownership ───────────────────────────────────────────────
chown -R www-data:www-data /var/www/html 2>/dev/null || true

# ── 4. Start PHP-FPM (background) ──────────────────────────────────
log "Starting PHP-FPM..."
php-fpm -D

# ── 5. Start web server (foreground) ───────────────────────────────
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

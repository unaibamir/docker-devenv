# Docker Dev Environments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a unified Docker environment system at `~/sites/docker-envs/` with a `dev` CLI that bootstraps WordPress, Laravel, and generic PHP projects in seconds.

**Architecture:** Single multi-stage Dockerfile (PHP-FPM + nginx/apache in one container), Compose `include` for per-project overrides, host MySQL/Redis via DBngin. `dev` CLI wraps all Docker operations.

**Tech Stack:** Docker + Docker Compose v2.40+, PHP 7.4-8.4 FPM Alpine, nginx/apache Alpine, Bash CLI

**Spec:** `docs/superpowers/specs/2026-04-07-docker-dev-environments-design.md`

---

## File Map

```
~/sites/docker-envs/                    # NEW directory (git repo)
├── Dockerfile                          # multi-stage: php-base → server-nginx/server-apache → final
├── entrypoint.sh                       # project-type-aware: WP download, Laravel composer, start services
├── dev                                 # CLI script: init/up/down/shell/test/lint/xdebug/php/web
├── compose/
│   ├── base.yml                        # core php service, ports, env, healthcheck, shared cache volumes
│   ├── wordpress.yml                   # wp_core volume, plugin bind mount, nginx config mount
│   ├── laravel.yml                     # vendor + node_modules volumes, code bind mount
│   └── package.yml                     # minimal, no web server
├── nginx/
│   ├── wordpress.conf                  # try_files + fastcgi_pass 127.0.0.1:9000
│   └── laravel.conf                    # same pattern, root at /public
├── apache/
│   ├── wordpress.conf                  # AllowOverride All + proxy:fcgi
│   └── laravel.conf                    # same, docroot /public
├── php/
│   ├── php.ini                         # upload_max=64M, memory_limit=256M, display_errors=On
│   ├── xdebug-on.ini                  # mode=debug, client_host=host.docker.internal
│   └── xdebug-off.ini                 # extension disabled
├── templates/
│   ├── wordpress.env                   # .env template for WP projects
│   ├── laravel.env                     # .env template for Laravel projects
│   ├── package.env                     # .env template for generic PHP
│   ├── docker-compose.wordpress.yml    # template compose for WP projects
│   ├── docker-compose.laravel.yml      # template compose for Laravel projects
│   └── docker-compose.package.yml      # template compose for PHP package projects
├── seeds/
│   └── wordpress-base.sh              # WP-CLI test data seeder
└── plugins/                            # local premium plugins (manual placement)
    └── .gitkeep
```

---

### Task 1: Directory Structure + Git Init

**Files:**
- Create: `~/sites/docker-envs/` and all subdirectories
- Create: `~/sites/docker-envs/.gitignore`

- [ ] **Step 1: Create directory tree**

```bash
mkdir -p ~/sites/docker-envs/{compose,nginx,apache,php,templates,seeds,plugins}
```

- [ ] **Step 2: Create .gitignore**

Create `~/sites/docker-envs/.gitignore`:

```gitignore
# Local overrides
.env
*.log

# OS
.DS_Store
Thumbs.db
```

- [ ] **Step 3: Create plugins/.gitkeep**

Create `~/sites/docker-envs/plugins/.gitkeep` (empty file).

- [ ] **Step 4: Init git repo**

```bash
cd ~/sites/docker-envs && git init
```

- [ ] **Step 5: Commit**

```bash
cd ~/sites/docker-envs
git add -A
git commit -m "chore: scaffold docker-envs directory structure"
```

---

### Task 2: PHP Config Files

**Files:**
- Create: `~/sites/docker-envs/php/php.ini`
- Create: `~/sites/docker-envs/php/xdebug-on.ini`
- Create: `~/sites/docker-envs/php/xdebug-off.ini`

- [ ] **Step 1: Write php.ini**

Create `~/sites/docker-envs/php/php.ini`:

```ini
[PHP]
upload_max_filesize = 64M
post_max_size = 64M
memory_limit = 256M
max_execution_time = 300
max_input_vars = 3000
display_errors = On
display_startup_errors = On
error_reporting = E_ALL
log_errors = On
error_log = /var/log/php-errors.log

[opcache]
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 0
opcache.validate_timestamps = 1

[Date]
date.timezone = UTC
```

- [ ] **Step 2: Write xdebug-on.ini**

Create `~/sites/docker-envs/php/xdebug-on.ini`:

```ini
[xdebug]
zend_extension=xdebug
xdebug.mode=debug
xdebug.client_host=host.docker.internal
xdebug.client_port=9003
xdebug.start_with_request=yes
xdebug.discover_client_host=0
xdebug.idekey=VSCODE
xdebug.log_level=0
```

- [ ] **Step 3: Write xdebug-off.ini**

Create `~/sites/docker-envs/php/xdebug-off.ini`:

```ini
[xdebug]
; Xdebug disabled — use `dev xdebug on` to enable
; zend_extension=xdebug
xdebug.mode=off
```

- [ ] **Step 4: Commit**

```bash
cd ~/sites/docker-envs
git add php/
git commit -m "feat: add PHP and Xdebug config files"
```

---

### Task 3: Web Server Config Files

**Files:**
- Create: `~/sites/docker-envs/nginx/wordpress.conf`
- Create: `~/sites/docker-envs/nginx/laravel.conf`
- Create: `~/sites/docker-envs/apache/wordpress.conf`
- Create: `~/sites/docker-envs/apache/laravel.conf`

- [ ] **Step 1: Write nginx/wordpress.conf**

Create `~/sites/docker-envs/nginx/wordpress.conf`:

```nginx
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.php;
    client_max_body_size 64M;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }

    location /healthcheck {
        access_log off;
        return 200 "ok";
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {
        expires max;
        log_not_found off;
    }
}
```

- [ ] **Step 2: Write nginx/laravel.conf**

Create `~/sites/docker-envs/nginx/laravel.conf`:

```nginx
server {
    listen 80;
    server_name _;
    root /var/www/html/public;
    index index.php;
    client_max_body_size 64M;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }

    location /healthcheck {
        access_log off;
        return 200 "ok";
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {
        expires max;
        log_not_found off;
    }
}
```

- [ ] **Step 3: Write apache/wordpress.conf**

Create `~/sites/docker-envs/apache/wordpress.conf`:

```apache
<VirtualHost *:80>
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:fcgi://127.0.0.1:9000"
    </FilesMatch>

    <Location /healthcheck>
        SetHandler none
        Require all granted
    </Location>

    ErrorLog /dev/stderr
    CustomLog /dev/stdout combined
</VirtualHost>
```

- [ ] **Step 4: Write apache/laravel.conf**

Create `~/sites/docker-envs/apache/laravel.conf`:

```apache
<VirtualHost *:80>
    DocumentRoot /var/www/html/public

    <Directory /var/www/html/public>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:fcgi://127.0.0.1:9000"
    </FilesMatch>

    <Location /healthcheck>
        SetHandler none
        Require all granted
    </Location>

    ErrorLog /dev/stderr
    CustomLog /dev/stdout combined
</VirtualHost>
```

- [ ] **Step 5: Commit**

```bash
cd ~/sites/docker-envs
git add nginx/ apache/
git commit -m "feat: add nginx and apache config files for WordPress and Laravel"
```

---

### Task 4: Dockerfile

**Files:**
- Create: `~/sites/docker-envs/Dockerfile`

- [ ] **Step 1: Write Dockerfile**

Create `~/sites/docker-envs/Dockerfile`:

```dockerfile
ARG PHP_VERSION=8.3
ARG WEB_SERVER=nginx

# ── PHP base (shared across all project types) ──────────────────────
FROM php:${PHP_VERSION}-fpm-alpine AS php-base
ARG PHP_VERSION

# System deps
RUN apk add --no-cache \
    bash \
    curl \
    freetype-dev \
    git \
    icu-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libxml2-dev \
    libzip-dev \
    linux-headers \
    oniguruma-dev \
    unzip \
    zip \
    $PHPIZE_DEPS \
    nodejs \
    npm

# PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    bcmath \
    exif \
    gd \
    intl \
    mbstring \
    mysqli \
    opcache \
    pdo_mysql \
    soap \
    zip

# Xdebug — version-aware (PHP 7.4 needs xdebug 3.1.x, PHP 8.0 needs 3.3.x)
RUN PHP_MAJOR_MINOR=$(echo "${PHP_VERSION}" | cut -d. -f1,2) \
    && if [ "$PHP_MAJOR_MINOR" = "7.4" ]; then \
        pecl install xdebug-3.1.6; \
    elif [ "$PHP_MAJOR_MINOR" = "8.0" ]; then \
        pecl install xdebug-3.3.2; \
    else \
        pecl install xdebug; \
    fi \
    && docker-php-ext-enable xdebug

# Redis extension
RUN pecl install redis && docker-php-ext-enable redis

# Composer 2
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# WP-CLI
RUN curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

# Match macOS user UID for permission-free bind mounts
ARG HOST_UID=501
RUN deluser www-data 2>/dev/null || true \
    && addgroup -g 82 www-data 2>/dev/null || true \
    && adduser -D -u ${HOST_UID} -G www-data -s /bin/bash www-data 2>/dev/null || true

# Create log file
RUN touch /var/log/php-errors.log && chown www-data:www-data /var/log/php-errors.log

# ── Nginx variant ───────────────────────────────────────────────────
FROM php-base AS server-nginx
RUN apk add --no-cache nginx \
    && mkdir -p /run/nginx \
    && chown -R www-data:www-data /run/nginx /var/log/nginx

# ── Apache variant ──────────────────────────────────────────────────
FROM php-base AS server-apache
RUN apk add --no-cache apache2 apache2-proxy \
    && sed -i 's/^#LoadModule rewrite_module/LoadModule rewrite_module/' /etc/apache2/httpd.conf \
    && sed -i 's/^#LoadModule proxy_module/LoadModule proxy_module/' /etc/apache2/httpd.conf \
    && sed -i 's/^#LoadModule proxy_fcgi_module/LoadModule proxy_fcgi_module/' /etc/apache2/httpd.conf \
    && mkdir -p /run/apache2

# ── Final (selected by WEB_SERVER ARG) ──────────────────────────────
FROM server-${WEB_SERVER} AS final

WORKDIR /var/www/html
EXPOSE 80

ENTRYPOINT ["entrypoint.sh"]
CMD []
```

- [ ] **Step 2: Commit**

```bash
cd ~/sites/docker-envs
git add Dockerfile
git commit -m "feat: add multi-stage Dockerfile with PHP version and web server selection"
```

---

### Task 5: Entrypoint Script

**Files:**
- Create: `~/sites/docker-envs/entrypoint.sh`

- [ ] **Step 1: Write entrypoint.sh**

Create `~/sites/docker-envs/entrypoint.sh`:

```bash
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x ~/sites/docker-envs/entrypoint.sh
```

- [ ] **Step 3: Commit**

```bash
cd ~/sites/docker-envs
git add entrypoint.sh
git commit -m "feat: add entrypoint script with WP download, Laravel setup, and server startup"
```

---

### Task 6: Compose Files

**Files:**
- Create: `~/sites/docker-envs/compose/base.yml`
- Create: `~/sites/docker-envs/compose/wordpress.yml`
- Create: `~/sites/docker-envs/compose/laravel.yml`
- Create: `~/sites/docker-envs/compose/package.yml`

- [ ] **Step 1: Write compose/base.yml**

Create `~/sites/docker-envs/compose/base.yml`:

```yaml
services:
  php:
    image: devenv-php${PHP_VERSION:-8.3}-${WEB_SERVER:-nginx}
    build:
      context: ..
      dockerfile: Dockerfile
      args:
        PHP_VERSION: ${PHP_VERSION:-8.3}
        WEB_SERVER: ${WEB_SERVER:-nginx}
        HOST_UID: ${HOST_UID:-501}
    container_name: ${COMPOSE_PROJECT_NAME:-dev}-php
    ports:
      - "${HTTP_PORT:-8080}:80"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      COMPOSE_PROJECT_NAME: ${COMPOSE_PROJECT_NAME:-dev}
      PROJECT_TYPE: ${PROJECT_TYPE:-wordpress}
      WEB_SERVER: ${WEB_SERVER:-nginx}
      HTTP_PORT: ${HTTP_PORT:-8080}
      DB_HOST: host.docker.internal
      DB_PORT: ${DB_PORT:-3306}
      DB_NAME: ${DB_NAME:-devdb}
      DB_USER: ${DB_USER:-root}
      DB_PASSWORD: ${DB_PASSWORD:-}
      REDIS_HOST: host.docker.internal
      REDIS_PORT: ${REDIS_PORT:-6379}
      WP_VERSION: ${WP_VERSION:-latest}
      PLUGIN_SLUG: ${PLUGIN_SLUG:-}
      XDEBUG_MODE: ${XDEBUG_MODE:-off}
    volumes:
      - ../php/php.ini:/usr/local/etc/php/conf.d/99-custom.ini:ro
      - ../php/xdebug-off.ini:/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini:ro
      - ../entrypoint.sh:/usr/local/bin/entrypoint.sh:ro
      - dev_composer_cache:/home/www-data/.composer/cache
      - dev_npm_cache:/home/www-data/.npm
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost/healthcheck"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 30s

volumes:
  dev_composer_cache:
    external: true
    name: dev_composer_cache
  dev_npm_cache:
    external: true
    name: dev_npm_cache
```

- [ ] **Step 2: Write compose/wordpress.yml**

Create `~/sites/docker-envs/compose/wordpress.yml`:

```yaml
services:
  php:
    volumes:
      - wp_core:/var/www/html
      - ${PROJECT_ROOT:-.}:/var/www/html/wp-content/plugins/${PLUGIN_SLUG}:cached
      - ../nginx/wordpress.conf:/etc/nginx/http.d/default.conf:ro

volumes:
  wp_core:
    name: ${COMPOSE_PROJECT_NAME:-dev}-wp-core
```

- [ ] **Step 3: Write compose/laravel.yml**

Create `~/sites/docker-envs/compose/laravel.yml`:

```yaml
services:
  php:
    volumes:
      - ${PROJECT_ROOT:-.}:/var/www/html:cached
      - laravel_vendor:/var/www/html/vendor
      - laravel_node_modules:/var/www/html/node_modules
      - ../nginx/laravel.conf:/etc/nginx/http.d/default.conf:ro

volumes:
  laravel_vendor:
    name: ${COMPOSE_PROJECT_NAME:-dev}-vendor
  laravel_node_modules:
    name: ${COMPOSE_PROJECT_NAME:-dev}-node-modules
```

- [ ] **Step 4: Write compose/package.yml**

Create `~/sites/docker-envs/compose/package.yml`:

```yaml
services:
  php:
    volumes:
      - ${PROJECT_ROOT:-.}:/var/www/html:cached
    healthcheck:
      test: ["CMD", "php", "-r", "echo 'ok';"]
      interval: 10s
      timeout: 3s
      retries: 3
    command: ["php-fpm", "-F"]
```

- [ ] **Step 5: Commit**

```bash
cd ~/sites/docker-envs
git add compose/
git commit -m "feat: add compose files for base, wordpress, laravel, and package types"
```

---

### Task 7: .env Templates + Project Compose Templates

**Files:**
- Create: `~/sites/docker-envs/templates/wordpress.env`
- Create: `~/sites/docker-envs/templates/laravel.env`
- Create: `~/sites/docker-envs/templates/package.env`
- Create: `~/sites/docker-envs/templates/docker-compose.wordpress.yml`
- Create: `~/sites/docker-envs/templates/docker-compose.laravel.yml`
- Create: `~/sites/docker-envs/templates/docker-compose.package.yml`

- [ ] **Step 1: Write templates/wordpress.env**

Create `~/sites/docker-envs/templates/wordpress.env`:

```bash
COMPOSE_PROJECT_NAME=__PROJECT_NAME__
PROJECT_TYPE=wordpress
PROJECT_ROOT=.

PHP_VERSION=8.3
WEB_SERVER=nginx
HTTP_PORT=__HTTP_PORT__

DB_NAME=wp___PROJECT_NAME__
DB_USER=root
DB_PASSWORD=
DB_PORT=3306
REDIS_PORT=6379

WP_VERSION=latest
PLUGIN_SLUG=__PROJECT_NAME__

XDEBUG_MODE=off
HOST_UID=__HOST_UID__
```

- [ ] **Step 2: Write templates/laravel.env**

Create `~/sites/docker-envs/templates/laravel.env`:

```bash
COMPOSE_PROJECT_NAME=__PROJECT_NAME__
PROJECT_TYPE=laravel
PROJECT_ROOT=.

PHP_VERSION=8.3
WEB_SERVER=nginx
HTTP_PORT=__HTTP_PORT__

DB_NAME=__PROJECT_NAME__
DB_USER=root
DB_PASSWORD=
DB_PORT=3306
REDIS_PORT=6379

XDEBUG_MODE=off
HOST_UID=__HOST_UID__
```

- [ ] **Step 3: Write templates/package.env**

Create `~/sites/docker-envs/templates/package.env`:

```bash
COMPOSE_PROJECT_NAME=__PROJECT_NAME__
PROJECT_TYPE=package
PROJECT_ROOT=.

PHP_VERSION=8.3
WEB_SERVER=nginx
HTTP_PORT=__HTTP_PORT__

XDEBUG_MODE=off
HOST_UID=__HOST_UID__
```

- [ ] **Step 4: Write templates/docker-compose.wordpress.yml**

Create `~/sites/docker-envs/templates/docker-compose.wordpress.yml`:

```yaml
include:
  - path: ../docker-envs/compose/base.yml
  - path: ../docker-envs/compose/wordpress.yml
```

- [ ] **Step 5: Write templates/docker-compose.laravel.yml**

Create `~/sites/docker-envs/templates/docker-compose.laravel.yml`:

```yaml
include:
  - path: ../docker-envs/compose/base.yml
  - path: ../docker-envs/compose/laravel.yml
```

- [ ] **Step 6: Write templates/docker-compose.package.yml**

Create `~/sites/docker-envs/templates/docker-compose.package.yml`:

```yaml
include:
  - path: ../docker-envs/compose/base.yml
  - path: ../docker-envs/compose/package.yml
```

- [ ] **Step 7: Commit**

```bash
cd ~/sites/docker-envs
git add templates/
git commit -m "feat: add .env and docker-compose templates for all project types"
```

---

### Task 8: WordPress Seed Script

**Files:**
- Create: `~/sites/docker-envs/seeds/wordpress-base.sh`

- [ ] **Step 1: Write seeds/wordpress-base.sh**

Create `~/sites/docker-envs/seeds/wordpress-base.sh`:

```bash
#!/bin/bash
# WordPress test data seeder — run via: dev seed
set -e

WP="wp --allow-root --path=/var/www/html"

echo "[seed] Creating test users..."
$WP user create editor editor@local.test --role=editor --user_pass=editor 2>/dev/null || true
$WP user create author author@local.test --role=author --user_pass=author 2>/dev/null || true
$WP user create subscriber sub@local.test --role=subscriber --user_pass=subscriber 2>/dev/null || true

echo "[seed] Creating test categories..."
$WP term create category "News" --slug=news 2>/dev/null || true
$WP term create category "Tutorials" --slug=tutorials 2>/dev/null || true
$WP term create category "Updates" --slug=updates 2>/dev/null || true

echo "[seed] Creating test posts..."
for i in $(seq 1 10); do
    $WP post create \
        --post_type=post \
        --post_status=publish \
        --post_title="Test Post ${i}" \
        --post_content="This is test post number ${i}. Lorem ipsum dolor sit amet." \
        --post_author=1 \
        2>/dev/null || true
done

echo "[seed] Creating test pages..."
$WP post create --post_type=page --post_status=publish --post_title="About" --post_content="About page content." 2>/dev/null || true
$WP post create --post_type=page --post_status=publish --post_title="Contact" --post_content="Contact page content." 2>/dev/null || true

echo "[seed] Updating permalink structure..."
$WP rewrite structure '/%postname%/' --hard 2>/dev/null || true
$WP rewrite flush --hard 2>/dev/null || true

echo "[seed] Done. Admin credentials: admin / admin"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x ~/sites/docker-envs/seeds/wordpress-base.sh
```

- [ ] **Step 3: Commit**

```bash
cd ~/sites/docker-envs
git add seeds/
git commit -m "feat: add WordPress base seed script"
```

---

### Task 9: `dev` CLI Script

**Files:**
- Create: `~/sites/docker-envs/dev`

This is the largest task. The `dev` script is a bash dispatcher with all commands.

- [ ] **Step 1: Write the dev CLI script**

Create `~/sites/docker-envs/dev`:

```bash
#!/bin/bash
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────
DEVENV_DIR="$(cd "$(dirname "$0")" && pwd)"
SITES_DIR="$(dirname "$DEVENV_DIR")"
VERSION="1.0.0"

# ── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[dev]${NC} $*"; }
warn()  { echo -e "${YELLOW}[dev]${NC} $*"; }
error() { echo -e "${RED}[dev]${NC} $*" >&2; }
info()  { echo -e "${BLUE}[dev]${NC} $*"; }

# ── Project Resolution ───────────────────────────────────────────────
# Walk up from CWD looking for docker-compose.yml with docker-envs include
find_project_dir() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/docker-compose.yml" ] && grep -q "docker-envs" "$dir/docker-compose.yml" 2>/dev/null; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

require_project() {
    PROJECT_DIR=$(find_project_dir) || {
        error "No devenv project found. Run 'dev init <type> <name>' first."
        exit 1
    }
    cd "$PROJECT_DIR"
}

dc() {
    docker compose "$@"
}

# ── Find next available port ─────────────────────────────────────────
find_available_port() {
    local port="${1:-8080}"
    local max=$((port + 100))
    while [ "$port" -lt "$max" ]; do
        if ! lsof -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done
    error "No available port found in range ${1}-${max}"
    exit 1
}

# ── Commands ─────────────────────────────────────────────────────────

cmd_setup() {
    log "Setting up devenv..."

    # Check Docker
    if ! command -v docker &>/dev/null; then
        error "Docker not found. Install Docker Desktop first."
        exit 1
    fi

    # Check Docker Compose
    if ! docker compose version &>/dev/null; then
        error "Docker Compose not found."
        exit 1
    fi

    # Create shared external volumes
    docker volume create dev_composer_cache 2>/dev/null && log "Created dev_composer_cache volume" || log "dev_composer_cache volume exists"
    docker volume create dev_npm_cache 2>/dev/null && log "Created dev_npm_cache volume" || log "dev_npm_cache volume exists"

    # Check MySQL
    if mysql -u root -e "SELECT 1" &>/dev/null 2>&1; then
        log "MySQL connection: OK"
    else
        warn "MySQL not reachable via 'mysql -u root'. Make sure DBngin is running."
    fi

    log "Setup complete."
}

cmd_build_all() {
    log "Building all PHP + server image combos..."
    local servers="nginx apache"
    local versions="7.4 8.0 8.1 8.2 8.3 8.4"

    for version in $versions; do
        for server in $servers; do
            local tag="devenv-php${version}-${server}"
            log "Building ${tag}..."
            docker build \
                --build-arg PHP_VERSION="$version" \
                --build-arg WEB_SERVER="$server" \
                --build-arg HOST_UID="$(id -u)" \
                -t "$tag" \
                "$DEVENV_DIR" || {
                    warn "Failed to build ${tag} — skipping"
                    continue
                }
        done
    done
    log "All images built."
}

cmd_init() {
    local type="${1:-}"
    local name="${2:-}"

    if [ -z "$type" ] || [ -z "$name" ]; then
        error "Usage: dev init <type> <name>"
        error "Types: wordpress, laravel, package"
        exit 1
    fi

    # Validate type
    case "$type" in
        wordpress|laravel|package) ;;
        *) error "Unknown type: $type. Use: wordpress, laravel, package"; exit 1 ;;
    esac

    local project_dir="${SITES_DIR}/${name}"

    if [ -d "$project_dir" ] && [ -f "$project_dir/docker-compose.yml" ]; then
        error "Project already exists at ${project_dir}"
        exit 1
    fi

    mkdir -p "$project_dir"

    # Find available port
    local port
    port=$(find_available_port 8080)

    # Copy .env template
    local env_template="${DEVENV_DIR}/templates/${type}.env"
    local host_uid
    host_uid=$(id -u)
    local safe_name
    safe_name=$(echo "$name" | tr '-' '_')

    sed -e "s/__PROJECT_NAME__/${name}/g" \
        -e "s/__HTTP_PORT__/${port}/g" \
        -e "s/__HOST_UID__/${host_uid}/g" \
        "$env_template" > "$project_dir/.env"

    # Fix DB_NAME for wordpress (use underscores)
    if [ "$type" = "wordpress" ]; then
        sed -i '' "s/DB_NAME=wp___PROJECT_NAME__/DB_NAME=wp_${safe_name}/" "$project_dir/.env"
    elif [ "$type" = "laravel" ]; then
        sed -i '' "s/DB_NAME=__PROJECT_NAME__/DB_NAME=${safe_name}/" "$project_dir/.env"
    fi

    # Copy compose template
    cp "${DEVENV_DIR}/templates/docker-compose.${type}.yml" "$project_dir/docker-compose.yml"

    # Create DB on host MySQL
    if [ "$type" != "package" ]; then
        local db_name
        if [ "$type" = "wordpress" ]; then
            db_name="wp_${safe_name}"
        else
            db_name="${safe_name}"
        fi
        if mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\`" 2>/dev/null; then
            log "Created database: ${db_name}"
        else
            warn "Could not create database '${db_name}'. Create it manually."
        fi
    fi

    log "Project initialized at ${project_dir}"
    info "  Type:    ${type}"
    info "  Port:    ${port}"
    info "  URL:     http://localhost:${port}"
    echo ""
    log "Next: cd ${project_dir} && dev up"
}

cmd_up() {
    require_project
    log "Starting containers..."
    dc up -d --build
    log "Running at http://localhost:$(grep HTTP_PORT .env 2>/dev/null | cut -d= -f2 || echo 8080)"
}

cmd_down() {
    require_project
    log "Stopping containers..."
    dc down
}

cmd_clean() {
    require_project
    warn "Removing containers AND volumes..."
    dc down -v
    log "Cleaned. Next 'dev up' will re-download/re-install."
}

cmd_shell() {
    require_project
    dc exec php bash
}

cmd_logs() {
    require_project
    dc logs "$@"
}

cmd_test() {
    require_project
    dc exec php sh -c 'if [ -f vendor/bin/pest ]; then vendor/bin/pest '"$*"'; elif [ -f vendor/bin/phpunit ]; then vendor/bin/phpunit '"$*"'; else echo "No test runner found. Install phpunit or pest via composer."; exit 1; fi'
}

cmd_lint() {
    require_project
    local fix=""
    if [ "${1:-}" = "--fix" ]; then
        fix="--fix"
        shift
    fi

    # PHPStan
    if dc exec php test -f vendor/bin/phpstan 2>/dev/null; then
        log "Running PHPStan..."
        dc exec php vendor/bin/phpstan analyse "$@" || true
    fi

    # Pint
    if dc exec php test -f vendor/bin/pint 2>/dev/null; then
        if [ -n "$fix" ]; then
            log "Running Pint (fix mode)..."
            dc exec php vendor/bin/pint "$@"
        else
            log "Running Pint (test mode)..."
            dc exec php vendor/bin/pint --test "$@"
        fi
    fi
}

cmd_wp() {
    require_project
    dc exec php wp --allow-root --path=/var/www/html "$@"
}

cmd_artisan() {
    require_project
    dc exec php php artisan "$@"
}

cmd_composer() {
    require_project
    dc exec php composer "$@"
}

cmd_npm() {
    require_project
    dc exec php npm "$@"
}

cmd_seed() {
    require_project
    local project_type
    project_type=$(grep PROJECT_TYPE .env 2>/dev/null | cut -d= -f2)

    if [ "$project_type" = "wordpress" ]; then
        if [ -f seeds/seed.sh ]; then
            log "Running project seed..."
            dc exec php bash /var/www/html/wp-content/plugins/*/seeds/seed.sh 2>/dev/null || \
            dc exec php bash -c "cat /dev/stdin | bash" < seeds/seed.sh
        else
            log "Running base WordPress seed..."
            dc exec php bash < "${DEVENV_DIR}/seeds/wordpress-base.sh"
        fi
    elif [ "$project_type" = "laravel" ]; then
        log "Running Laravel seed..."
        dc exec php php artisan db:seed "$@"
    else
        warn "No seed command for project type: ${project_type}"
    fi
}

cmd_php() {
    local version="${1:-}"
    if [ -z "$version" ]; then
        error "Usage: dev php <version>"
        error "Versions: 7.4, 8.0, 8.1, 8.2, 8.3, 8.4"
        exit 1
    fi

    require_project

    # Validate version
    case "$version" in
        7.4|8.0|8.1|8.2|8.3|8.4) ;;
        *) error "Invalid PHP version: $version"; exit 1 ;;
    esac

    sed -i '' "s/^PHP_VERSION=.*/PHP_VERSION=${version}/" .env
    log "Switched to PHP ${version}. Rebuilding..."
    dc up -d --build
    log "PHP ${version} running."
}

cmd_web() {
    local server="${1:-}"
    if [ -z "$server" ]; then
        error "Usage: dev web <nginx|apache>"
        exit 1
    fi

    require_project

    case "$server" in
        nginx|apache) ;;
        *) error "Invalid server: $server. Use: nginx, apache"; exit 1 ;;
    esac

    # Update .env
    sed -i '' "s/^WEB_SERVER=.*/WEB_SERVER=${server}/" .env

    # Swap nginx config mount in compose if needed
    # The compose files mount the correct config based on WEB_SERVER
    log "Switched to ${server}. Rebuilding..."
    dc up -d --build
    log "${server} running."
}

cmd_xdebug() {
    local mode="${1:-}"
    require_project

    case "$mode" in
        on)
            log "Enabling Xdebug (debug mode)..."
            dc cp "${DEVENV_DIR}/php/xdebug-on.ini" php:/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
            dc exec php kill -USR2 1
            log "Xdebug enabled. Connect your IDE to port 9003."
            ;;
        off)
            log "Disabling Xdebug..."
            dc cp "${DEVENV_DIR}/php/xdebug-off.ini" php:/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
            dc exec php kill -USR2 1
            log "Xdebug disabled."
            ;;
        coverage)
            log "Enabling Xdebug (coverage mode)..."
            dc exec php sh -c 'cat > /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini << EOF
[xdebug]
zend_extension=xdebug
xdebug.mode=coverage
EOF'
            dc exec php kill -USR2 1
            log "Xdebug coverage mode enabled."
            ;;
        status)
            dc exec php php -r "echo 'Xdebug: ' . (extension_loaded('xdebug') ? 'loaded (mode=' . ini_get('xdebug.mode') . ')' : 'not loaded') . PHP_EOL;"
            ;;
        *)
            error "Usage: dev xdebug <on|off|coverage|status>"
            exit 1
            ;;
    esac
}

cmd_ps() {
    log "Running devenv projects:"
    echo ""
    printf "%-25s %-12s %-8s %-10s %s\n" "PROJECT" "TYPE" "PORT" "PHP" "STATUS"
    printf "%-25s %-12s %-8s %-10s %s\n" "-------" "----" "----" "---" "------"

    for env_file in "${SITES_DIR}"/*/".env"; do
        [ -f "$env_file" ] || continue
        local dir
        dir=$(dirname "$env_file")
        [ -f "$dir/docker-compose.yml" ] && grep -q "docker-envs" "$dir/docker-compose.yml" 2>/dev/null || continue

        local name type port php_ver status
        name=$(basename "$dir")
        type=$(grep "^PROJECT_TYPE=" "$env_file" 2>/dev/null | cut -d= -f2)
        port=$(grep "^HTTP_PORT=" "$env_file" 2>/dev/null | cut -d= -f2)
        php_ver=$(grep "^PHP_VERSION=" "$env_file" 2>/dev/null | cut -d= -f2)

        # Check if running
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${name}-php"; then
            status="${GREEN}running${NC}"
        else
            status="stopped"
        fi

        printf "%-25s %-12s %-8s %-10s " "$name" "$type" "$port" "$php_ver"
        echo -e "$status"
    done
}

cmd_status() {
    require_project
    local name
    name=$(basename "$PROJECT_DIR")

    echo ""
    info "Project: ${name}"
    info "Dir:     ${PROJECT_DIR}"
    grep -E "^(PROJECT_TYPE|PHP_VERSION|WEB_SERVER|HTTP_PORT|DB_NAME|XDEBUG_MODE)=" .env 2>/dev/null | while IFS='=' read -r key val; do
        info "  ${key}: ${val}"
    done

    # Container status
    echo ""
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${name}-php"; then
        log "Container: running"
    else
        warn "Container: stopped"
    fi
}

cmd_help() {
    cat <<EOF
dev v${VERSION} — Docker dev environment manager

Usage: dev <command> [args]

Setup:
  setup                  One-time setup (create shared volumes, check deps)
  build-all              Pre-build all PHP + server image combos
  init <type> <name>     Bootstrap a new project (wordpress|laravel|package)

Lifecycle:
  up                     Start containers (builds if needed)
  down                   Stop containers
  clean                  Stop + remove volumes

Development:
  shell                  Open shell in container
  logs [-f]              View container logs
  wp <args>              WP-CLI passthrough
  artisan <args>         Laravel Artisan passthrough
  composer <args>        Composer passthrough
  npm <args>             npm passthrough
  seed                   Seed database with test data

Testing:
  test [args]            Run PHPUnit/Pest
  lint [--fix]           Run PHPStan + Pint

Switching:
  php <version>          Switch PHP (7.4|8.0|8.1|8.2|8.3|8.4)
  web <server>           Switch web server (nginx|apache)
  xdebug <on|off|coverage|status>  Toggle Xdebug

Info:
  ps                     List all devenv projects
  status                 Show current project config
  help                   Show this help
EOF
}

# ── Dispatcher ───────────────────────────────────────────────────────
main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$cmd" in
        setup)      cmd_setup "$@" ;;
        build-all)  cmd_build_all "$@" ;;
        init)       cmd_init "$@" ;;
        up)         cmd_up "$@" ;;
        down)       cmd_down "$@" ;;
        clean)      cmd_clean "$@" ;;
        shell|ssh)  cmd_shell "$@" ;;
        logs)       cmd_logs "$@" ;;
        test)       cmd_test "$@" ;;
        lint)       cmd_lint "$@" ;;
        wp)         cmd_wp "$@" ;;
        artisan)    cmd_artisan "$@" ;;
        composer)   cmd_composer "$@" ;;
        npm)        cmd_npm "$@" ;;
        seed)       cmd_seed "$@" ;;
        php)        cmd_php "$@" ;;
        web)        cmd_web "$@" ;;
        xdebug)     cmd_xdebug "$@" ;;
        ps)         cmd_ps "$@" ;;
        status)     cmd_status "$@" ;;
        help|-h|--help) cmd_help ;;
        *)          error "Unknown command: $cmd"; cmd_help; exit 1 ;;
    esac
}

main "$@"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x ~/sites/docker-envs/dev
```

- [ ] **Step 3: Commit**

```bash
cd ~/sites/docker-envs
git add dev
git commit -m "feat: add dev CLI script with all commands"
```

---

### Task 10: Add `dev` to PATH

- [ ] **Step 1: Create symlink or add to PATH**

Add to `~/.zshrc`:

```bash
export PATH="$HOME/sites/docker-envs:$PATH"
```

Then reload:

```bash
source ~/.zshrc
```

- [ ] **Step 2: Verify**

```bash
which dev
dev help
```

Expected: Shows the help output from the dev script.

---

### Task 11: Build First Image + Test WordPress End-to-End

- [ ] **Step 1: Run setup**

```bash
dev setup
```

Expected: Creates `dev_composer_cache` and `dev_npm_cache` volumes. Reports MySQL connection status.

- [ ] **Step 2: Build PHP 8.3 + nginx image**

```bash
cd ~/sites/docker-envs
docker build \
    --build-arg PHP_VERSION=8.3 \
    --build-arg WEB_SERVER=nginx \
    --build-arg HOST_UID=501 \
    -t devenv-php8.3-nginx \
    .
```

Expected: Image builds successfully. Verify with `docker images | grep devenv`.

- [ ] **Step 3: Init a test WordPress project**

```bash
dev init wordpress test-wp-plugin
```

Expected: Creates `~/sites/test-wp-plugin/` with `docker-compose.yml` and `.env`. Creates `wp_test_wp_plugin` database.

- [ ] **Step 4: Start the project**

```bash
cd ~/sites/test-wp-plugin
dev up
```

Expected: Container starts, downloads WordPress, installs it, activates plugin. Site accessible at http://localhost:PORT.

- [ ] **Step 5: Verify WP-CLI**

```bash
dev wp plugin list
dev wp user list
```

Expected: Shows plugin list with test-wp-plugin active. Shows admin user.

- [ ] **Step 6: Verify shell access**

```bash
dev shell
# inside container:
php -v
composer --version
node --version
wp --info
exit
```

Expected: All tools available inside the container.

- [ ] **Step 7: Test status and ps**

```bash
dev status
dev ps
```

Expected: Shows project config and running status.

- [ ] **Step 8: Cleanup test project**

```bash
dev down
cd ~/sites
rm -rf ~/sites/test-wp-plugin
mysql -u root -e "DROP DATABASE IF EXISTS wp_test_wp_plugin" 2>/dev/null || true
```

---

### Task 12: Test Laravel End-to-End

- [ ] **Step 1: Init a test Laravel project**

```bash
dev init laravel test-laravel
```

- [ ] **Step 2: Create a minimal Laravel app in the project dir**

```bash
cd ~/sites/test-laravel
dev shell
# inside container:
composer create-project laravel/laravel .
exit
```

Or from host if composer is available:
```bash
cd ~/sites/test-laravel
# The container will run composer install on first up via entrypoint
```

- [ ] **Step 3: Start and verify**

```bash
cd ~/sites/test-laravel
dev up
```

Expected: Container starts, runs composer install if vendor missing, Laravel welcome page at http://localhost:PORT.

- [ ] **Step 4: Test artisan**

```bash
dev artisan route:list
```

Expected: Shows Laravel routes.

- [ ] **Step 5: Cleanup**

```bash
dev down
cd ~/sites
rm -rf ~/sites/test-laravel
mysql -u root -e "DROP DATABASE IF EXISTS test_laravel" 2>/dev/null || true
```

---

### Task 13: Test Xdebug Toggle

- [ ] **Step 1: Start a project**

```bash
dev init wordpress xdebug-test
cd ~/sites/xdebug-test
dev up
```

- [ ] **Step 2: Check Xdebug is off by default**

```bash
dev xdebug status
```

Expected: Shows "Xdebug: loaded (mode=off)" or "not loaded".

- [ ] **Step 3: Toggle on**

```bash
dev xdebug on
dev xdebug status
```

Expected: Shows "Xdebug: loaded (mode=debug)".

- [ ] **Step 4: Toggle off**

```bash
dev xdebug off
dev xdebug status
```

Expected: Shows mode=off or not loaded.

- [ ] **Step 5: Cleanup**

```bash
dev clean
cd ~/sites
rm -rf ~/sites/xdebug-test
mysql -u root -e "DROP DATABASE IF EXISTS wp_xdebug_test" 2>/dev/null || true
```

---

### Task 14: Test PHP Version Switching

- [ ] **Step 1: Start a project on PHP 8.3**

```bash
dev init wordpress php-test
cd ~/sites/php-test
dev up
dev shell -c "php -v"  # or: docker compose exec php php -v
```

Expected: PHP 8.3.x.

- [ ] **Step 2: Switch to PHP 8.2**

```bash
dev php 8.2
docker compose exec php php -v
```

Expected: PHP 8.2.x. Container rebuilds and restarts.

- [ ] **Step 3: Switch to PHP 8.4**

```bash
dev php 8.4
docker compose exec php php -v
```

Expected: PHP 8.4.x.

- [ ] **Step 4: Cleanup**

```bash
dev clean
cd ~/sites
rm -rf ~/sites/php-test
mysql -u root -e "DROP DATABASE IF EXISTS wp_php_test" 2>/dev/null || true
```

---

### Task 15: Build All Images

- [ ] **Step 1: Build all 12 combos**

```bash
dev build-all
```

Expected: Builds `devenv-php{7.4,8.0,8.1,8.2,8.3,8.4}-{nginx,apache}`. Some PHP 7.4 extensions may have warnings but should complete.

- [ ] **Step 2: Verify images**

```bash
docker images | grep devenv | sort
```

Expected: 12 images listed.

- [ ] **Step 3: Commit any fixes**

If any Dockerfile adjustments were needed during testing, commit them:

```bash
cd ~/sites/docker-envs
git add -A
git commit -m "fix: adjust Dockerfile for all PHP version compatibility"
```

---

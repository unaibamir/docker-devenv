# Docker Dev Environments — Design Spec

## Context

Multiple PHP products (WordPress plugins, Laravel/Filament packages, generic PHP libraries) need local Docker environments for development and testing. Current setup is ad-hoc — each project has its own Docker config with different patterns. This creates a unified, lightweight system where spinning up a new project takes one command.

**Problem**: No consistent way to create, configure, and switch between Docker environments across product types.
**Outcome**: A `dev` CLI + shared Docker base that bootstraps any PHP project type in seconds, with switchable PHP versions and web servers.

---

## Architecture

### Central Base + Per-Project Overrides

```
~/sites/docker-envs/              # shared base (one repo)
~/sites/my-wp-plugin/             # project with thin docker-compose.yml
~/sites/my-laravel-pkg/           # another project, same pattern
```

Projects use Compose `include` to pull in shared definitions. All variation driven by `.env`.

### Host Services (NOT in Docker)

- **MySQL**: DBngin on host, port 3306
- **Redis**: DBngin on host, port 6379
- Containers connect via `host.docker.internal`

### What IS in Docker

- PHP-FPM (7.4 through 8.4, selectable)
- Web server (nginx OR apache, selectable)
- Composer 2, Node 20, npm, WP-CLI (all baked into PHP image)
- Xdebug (installed but disabled by default)

---

## Directory Structure

### Central Base: `~/sites/docker-envs/`

```
docker-envs/
├── Dockerfile                      # single multi-stage file
├── entrypoint.sh                   # project-type-aware startup
├── dev                             # CLI script (~300 lines bash)
├── compose/
│   ├── base.yml                    # core: php service + nginx/apache profiles
│   ├── wordpress.yml               # WP overlay: volumes, entrypoint, wp_core volume
│   ├── laravel.yml                 # Laravel overlay: vendor volume, node_modules volume
│   └── package.yml                 # bare PHP: minimal, no web server needed
├── nginx/
│   ├── wordpress.conf              # try_files + PHP-FPM proxy, root at /var/www/html/wordpress
│   └── laravel.conf                # try_files + PHP-FPM proxy, root at /var/www/html/public
├── apache/
│   ├── wordpress.conf              # AllowOverride All + proxy:fcgi
│   └── laravel.conf                # same pattern, different docroot
├── php/
│   ├── php.ini                     # shared: upload_max=64M, memory_limit=256M, error_reporting=E_ALL
│   ├── xdebug-on.ini              # mode=debug, client_host=host.docker.internal, start_with_request=yes
│   └── xdebug-off.ini             # zend_extension commented out
├── templates/
│   ├── wordpress.env               # .env template for WP projects
│   ├── laravel.env                 # .env template for Laravel projects
│   └── package.env                 # .env template for generic PHP
├── seeds/
│   └── wordpress-base.sh           # WP-CLI commands for test data (5 users, 10 posts)
└── plugins/                        # local premium plugins (BuddyBoss, ACF Pro — manual placement)
```

### Per-Project Files

```
~/sites/my-wp-plugin/
├── docker-compose.yml              # 3 lines: include base.yml + wordpress.yml
├── .env                            # project-specific config
└── (plugin source code)
```

**docker-compose.yml** (WordPress plugin):
```yaml
include:
  - path: ../docker-envs/compose/base.yml
  - path: ../docker-envs/compose/wordpress.yml
```

**docker-compose.yml** (Laravel package):
```yaml
include:
  - path: ../docker-envs/compose/base.yml
  - path: ../docker-envs/compose/laravel.yml
```

---

## Dockerfile: Single Multi-Stage

```dockerfile
ARG PHP_VERSION=8.3
ARG WEB_SERVER=nginx

# ── PHP base (shared across all project types) ──────────
FROM php:${PHP_VERSION}-fpm-alpine AS php-base
ARG PHP_VERSION

RUN apk add --no-cache \
    git unzip curl icu-dev libzip-dev libpng-dev libjpeg-turbo-dev \
    freetype-dev oniguruma-dev libxml2-dev linux-headers \
    $PHPIZE_DEPS nodejs npm

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    bcmath exif gd intl mbstring mysqli opcache pdo_mysql soap zip

# Xdebug — version-aware (7.4 needs xdebug 3.1.x)
RUN if [ "$(echo "${PHP_VERSION}" | cut -c1-3)" = "7.4" ]; then \
        pecl install xdebug-3.1.6; \
    else \
        pecl install xdebug; \
    fi && docker-php-ext-enable xdebug

RUN pecl install redis && docker-php-ext-enable redis

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

# Match macOS user UID for permission-free bind mounts
ARG HOST_UID=501
RUN deluser www-data 2>/dev/null || true \
    && adduser -D -u ${HOST_UID} -G www-data www-data

# ── Nginx variant ────────────────────────────────────────
FROM php-base AS server-nginx
RUN apk add --no-cache nginx
RUN mkdir -p /run/nginx

# ── Apache variant ───────────────────────────────────────
FROM php-base AS server-apache
RUN apk add --no-cache apache2 apache2-proxy
RUN sed -i 's/^#LoadModule rewrite_module/LoadModule rewrite_module/' /etc/apache2/httpd.conf \
    && sed -i 's/^#LoadModule proxy_fcgi_module/LoadModule proxy_fcgi_module/' /etc/apache2/httpd.conf

# ── Final (selected by WEB_SERVER ARG) ───────────────────
FROM server-${WEB_SERVER} AS final

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html
EXPOSE 80

ENTRYPOINT ["entrypoint.sh"]
```

**Image naming**: `devenv-php<version>-<server>` (e.g. `devenv-php83-nginx`).
Pre-build all 12 combos (6 PHP versions x 2 servers) via `dev build-all`.

---

## Compose Files

### `compose/base.yml`

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
    ports:
      - "${HTTP_PORT:-8080}:80"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      DB_HOST: host.docker.internal
      DB_PORT: ${DB_PORT:-3306}
      DB_NAME: ${DB_NAME:-devdb}
      DB_USER: ${DB_USER:-root}
      DB_PASSWORD: ${DB_PASSWORD:-}
      REDIS_HOST: host.docker.internal
      REDIS_PORT: ${REDIS_PORT:-6379}
      PROJECT_TYPE: ${PROJECT_TYPE:-wordpress}
      WEB_SERVER: ${WEB_SERVER:-nginx}
      WP_VERSION: ${WP_VERSION:-latest}
      PLUGIN_SLUG: ${PLUGIN_SLUG:-}
      XDEBUG_MODE: ${XDEBUG_MODE:-off}
    volumes:
      - ../php/php.ini:/usr/local/etc/php/conf.d/99-custom.ini:ro
      - ../php/xdebug-off.ini:/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini:ro
      - dev_composer_cache:/home/www-data/.composer/cache
      - dev_npm_cache:/home/www-data/.npm
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/healthcheck"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 20s

volumes:
  dev_composer_cache:
    external: true
    name: dev_composer_cache
  dev_npm_cache:
    external: true
    name: dev_npm_cache
```

### `compose/wordpress.yml`

```yaml
services:
  php:
    volumes:
      - ${PROJECT_ROOT:-.}:/var/www/html/wp-content/plugins/${PLUGIN_SLUG}:cached
      - wp_core:/var/www/html
      - ../nginx/wordpress.conf:/etc/nginx/http.d/default.conf:ro
      - ../entrypoint.sh:/usr/local/bin/entrypoint.sh:ro

volumes:
  wp_core:
    name: ${COMPOSE_PROJECT_NAME:-dev}-wp-core
```

### `compose/laravel.yml`

```yaml
services:
  php:
    volumes:
      - ${PROJECT_ROOT:-.}:/var/www/html:cached
      - laravel_vendor:/var/www/html/vendor
      - laravel_node_modules:/var/www/html/node_modules
      - ../nginx/laravel.conf:/etc/nginx/http.d/default.conf:ro
      - ../entrypoint.sh:/usr/local/bin/entrypoint.sh:ro

volumes:
  laravel_vendor:
    name: ${COMPOSE_PROJECT_NAME:-dev}-vendor
  laravel_node_modules:
    name: ${COMPOSE_PROJECT_NAME:-dev}-node-modules
```

### `compose/package.yml`

```yaml
services:
  php:
    volumes:
      - ${PROJECT_ROOT:-.}:/var/www/html:cached
      - ../entrypoint.sh:/usr/local/bin/entrypoint.sh:ro
    ports: []  # no web server needed
    command: ["php-fpm", "-F"]  # skip entrypoint web server startup
```

---

## Entrypoint Script

```bash
#!/bin/sh
set -e

# 1. Select web server config
if [ "$WEB_SERVER" = "nginx" ]; then
    # Config already mounted via compose volumes
    :
elif [ "$WEB_SERVER" = "apache" ]; then
    cp /etc/apache2/templates/${PROJECT_TYPE}.conf /etc/apache2/conf.d/app.conf
fi

# 2. WordPress: download core on first run
if [ "$PROJECT_TYPE" = "wordpress" ] && [ ! -f /var/www/html/wp-load.php ]; then
    echo "Downloading WordPress ${WP_VERSION}..."
    wp core download --version="${WP_VERSION}" --path=/var/www/html --allow-root
    wp config create \
        --path=/var/www/html \
        --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASSWORD}" \
        --dbhost="${DB_HOST}:${DB_PORT}" --allow-root \
        --extra-php <<'PHP'
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('SCRIPT_DEBUG', true);
define('FS_METHOD', 'direct');
PHP
    wp core install \
        --path=/var/www/html \
        --url="http://localhost:${HTTP_PORT:-80}" \
        --title="${COMPOSE_PROJECT_NAME:-Dev}" \
        --admin_user=admin --admin_password=admin \
        --admin_email=dev@local.test --skip-email --allow-root
    [ -n "$PLUGIN_SLUG" ] && wp plugin activate "$PLUGIN_SLUG" --allow-root --path=/var/www/html
fi

# 3. Laravel: composer install if vendor missing
if [ "$PROJECT_TYPE" = "laravel" ] && [ ! -f /var/www/html/vendor/autoload.php ]; then
    composer install --no-interaction --prefer-dist
fi

# 4. Create healthcheck endpoint
echo "ok" > /tmp/healthcheck.html

# 5. Fix ownership
chown -R www-data:www-data /var/www/html 2>/dev/null || true

# 6. Start PHP-FPM (background) + web server (foreground)
php-fpm -D

if [ "$WEB_SERVER" = "nginx" ]; then
    nginx -g "daemon off;"
elif [ "$WEB_SERVER" = "apache" ]; then
    httpd -D FOREGROUND
fi
```

---

## `.env` Templates

### `templates/wordpress.env`

```bash
COMPOSE_PROJECT_NAME=my-plugin
PROJECT_TYPE=wordpress
PROJECT_ROOT=.

PHP_VERSION=8.3
WEB_SERVER=nginx
HTTP_PORT=8080

DB_NAME=wp_my_plugin
DB_USER=root
DB_PASSWORD=
DB_PORT=3306
REDIS_PORT=6379

WP_VERSION=latest
PLUGIN_SLUG=my-plugin

XDEBUG_MODE=off
HOST_UID=501
```

### `templates/laravel.env`

```bash
COMPOSE_PROJECT_NAME=my-package
PROJECT_TYPE=laravel
PROJECT_ROOT=.

PHP_VERSION=8.3
WEB_SERVER=nginx
HTTP_PORT=8081

DB_NAME=my_package
DB_USER=root
DB_PASSWORD=
DB_PORT=3306
REDIS_PORT=6379

XDEBUG_MODE=off
HOST_UID=501
```

---

## `dev` CLI Commands

| Command | Action |
|---|---|
| `dev setup` | One-time: create shared cache volumes, verify Docker, verify DBngin |
| `dev build-all` | Pre-build all 12 PHP+server image combos |
| `dev init <type> <name>` | Bootstrap project: create dir, docker-compose.yml, .env, create DB |
| `dev up` | Start containers (builds image if needed) |
| `dev down` | Stop containers, keep volumes |
| `dev clean` | Stop + remove volumes (WP core re-downloads on next up) |
| `dev shell` | Shell into container |
| `dev logs [-f]` | Tail logs |
| `dev test [args]` | Run `vendor/bin/phpunit` inside container |
| `dev lint [--fix]` | Run PHPStan + Pint |
| `dev wp <args>` | WP-CLI passthrough |
| `dev artisan <args>` | Artisan passthrough |
| `dev composer <args>` | Composer passthrough |
| `dev npm <args>` | npm passthrough |
| `dev php <version>` | Switch PHP version (updates .env, rebuilds, restarts) |
| `dev web <nginx\|apache>` | Switch web server (updates .env, rebuilds, restarts) |
| `dev xdebug <on\|off\|coverage>` | Toggle Xdebug without rebuild (swaps ini, reloads FPM) |
| `dev ps` | List all running devenv projects with ports |
| `dev status` | Show current project config |

### How `dev` Resolves the Project

The `dev` script looks for `docker-compose.yml` in CWD (or parent dirs) that contains an `include` referencing `docker-envs/`. This tells it the project dir. All `docker compose` commands run from that dir.

---

## Xdebug Toggle (No Rebuild)

Xdebug is installed in every image. Two ini files exist:
- `xdebug-on.ini`: `xdebug.mode=debug`, `client_host=host.docker.internal`, `start_with_request=yes`
- `xdebug-off.ini`: extension line commented out

`dev xdebug on`:
```bash
docker compose cp ../docker-envs/php/xdebug-on.ini php:/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
docker compose exec php kill -USR2 1  # graceful PHP-FPM reload
```

Takes ~1 second. No container restart.

`dev xdebug coverage` sets `xdebug.mode=coverage` for test coverage runs.

---

## Port Management

Convention: each project gets a unique `HTTP_PORT` in `.env`.
- `dev init` auto-assigns next available port starting at 8080
- Checks `lsof -iTCP:<port> -sTCP:LISTEN` before assigning
- `dev ps` shows all project ports

---

## Performance Decisions

| Decision | Why |
|---|---|
| Alpine-based images | ~250MB vs ~500MB Debian. Faster pulls, less disk. |
| No MySQL/Redis in containers | Already on host via DBngin. Zero overhead. |
| Named volumes for WP core, vendor, node_modules | macOS bind mount perf is bad for large dirs. Named volumes use Linux VM storage. |
| Bind mount with `:cached` for project source | Your code is small (hundreds of files). `:cached` is fast enough. |
| Composer/npm cache as shared external volumes | Install speed: 45s -> 3s on repeat runs. |
| PHP-FPM + web server in single container | One container per project. No inter-container networking complexity. |
| Xdebug toggle via ini swap + FPM reload | No rebuild, no restart. 1 second. |

---

## Startup Flow

```
Cold start (first run, WordPress):
1. dev up
2. Compose builds image (if not cached): ~2-3 min first time
3. Container starts, entrypoint runs
4. WP core download: ~10 seconds
5. wp-config.php generated
6. wp core install: ~3 seconds
7. Plugin activated
8. Nginx starts
9. Site at localhost:8080
Total: ~3 min first time

Warm start (subsequent):
1. dev up
2. Image cached, container starts: ~2 seconds
3. Entrypoint skips WP download (wp-load.php exists)
4. Nginx starts
5. Site at localhost:8080
Total: ~2 seconds
```

---

## Testing Approach

### WordPress Plugins
- PHPUnit via `dev test` -> `vendor/bin/phpunit`
- Test DB: separate MySQL database `{project}_test` on host, created by `dev init`
- WP test scaffold available via `wp scaffold plugin-tests`

### Laravel Packages
- PHPUnit via `dev test` -> `vendor/bin/phpunit`
- Test DB: SQLite `:memory:` (default, set in phpunit.xml)
- Option to use MySQL test DB via `.env` override

### Static Analysis
- `dev lint` runs `vendor/bin/phpstan analyse` + `vendor/bin/pint --test`
- `dev lint --fix` runs Pint with auto-fix

---

## Implementation Order

1. `dev` CLI shell script (dispatcher + setup/init/up/down/shell)
2. Dockerfile (start with PHP 8.3 + nginx)
3. `compose/base.yml` + `compose/wordpress.yml`
4. Entrypoint script (WP download flow)
5. WordPress nginx config
6. `dev init wordpress` end-to-end working
7. `compose/laravel.yml` + Laravel entrypoint logic + config
8. `dev init laravel` end-to-end working
9. `compose/package.yml` for bare PHP
10. Xdebug toggle commands
11. PHP version switching + `dev build-all`
12. Apache variant (configs + Dockerfile stage)
13. `dev test`, `dev lint` commands
14. Port auto-assignment + `dev ps`

---

## Web Server Configs

### `nginx/wordpress.conf`
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

### `nginx/laravel.conf`
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
    }

    location /healthcheck {
        access_log off;
        return 200 "ok";
    }
}
```

### `apache/wordpress.conf`
```apache
<VirtualHost *:80>
    DocumentRoot /var/www/html
    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>
    <FilesMatch \.php$>
        SetHandler "proxy:fcgi://127.0.0.1:9000"
    </FilesMatch>
</VirtualHost>
```

### `apache/laravel.conf`
```apache
<VirtualHost *:80>
    DocumentRoot /var/www/html/public
    <Directory /var/www/html/public>
        AllowOverride All
        Require all granted
    </Directory>
    <FilesMatch \.php$>
        SetHandler "proxy:fcgi://127.0.0.1:9000"
    </FilesMatch>
</VirtualHost>
```

---

## Verification

After implementation, verify with:

1. `dev setup` — creates shared volumes, no errors
2. `dev init wordpress test-plugin` — creates project, DB, files
3. `cd ~/sites/test-plugin && dev up` — WP downloads, site loads at localhost:8080
4. `dev wp plugin list` — shows test-plugin active
5. `dev php 8.2` — switches PHP, site still works
6. `dev web apache` — switches to Apache, site still works
7. `dev xdebug on` — Xdebug connects to IDE
8. `dev test` — PHPUnit runs
9. `dev down && dev up` — warm start in ~2 seconds
10. `dev init laravel test-laravel` — Laravel project bootstraps
11. `dev artisan migrate` — migrations run against host MySQL
12. `dev ps` — shows both projects with ports

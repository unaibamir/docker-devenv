# docker-envs

> A `dev` CLI and shared Docker base that bootstraps WordPress plugin, Laravel/Filament, and generic PHP development environments on macOS.

## Features

- Single multi-stage Dockerfile supporting PHP 7.4, 8.0, 8.1, 8.2, 8.3, and 8.4
- Nginx and Apache web server variants, switchable without rebuild
- Per-project thin `docker-compose.yml` using Compose `include` to reference shared configs
- Host-side MySQL and Redis via DBngin (no database containers)
- `dev` CLI wrapping all Docker Compose operations
- Xdebug toggle (debug, coverage, off) without container rebuild
- Shared Composer and npm cache volumes across all projects
- Automatic WordPress core download, install, and plugin activation on first run
- Automatic `composer install` for Laravel projects on first run
- WordPress test data seeding via WP-CLI
- UID mapping for permission-free bind mounts on macOS

## Prerequisites

- **macOS** (uses `host.docker.internal` for host networking)
- **Docker Desktop** or **OrbStack** with Docker Compose v2
- **MySQL** running on the host (port 3306) -- [DBngin](https://dbngin.com/) recommended
- **Redis** running on the host (port 6379) -- optional, for Laravel/WordPress object cache
- Root-accessible MySQL (`mysql -u root` without password)

## Quick Start

```bash
# 1. Clone the repo into your sites directory
git clone <repo-url> ~/sites/docker-envs

# 2. Run one-time setup (creates shared cache volumes, checks deps)
~/sites/docker-envs/dev setup

# 2b. (Optional) Pre-fetch base images for faster builds
~/sites/docker-envs/dev pull

# 3. Add dev to your PATH
echo 'export PATH="$HOME/sites/docker-envs:$PATH"' >> ~/.zshrc && source ~/.zshrc

# 4. Create a WordPress plugin project
dev init wordpress my-plugin

# 5. Start it
cd ~/sites/my-plugin && dev up
```

Your WordPress site is now at `http://localhost:8080` (bound to `127.0.0.1` only, not accessible from LAN) with admin credentials `admin` / `admin`.

## Installation

```bash
# Clone into your sites directory (projects are created as siblings)
git clone <repo-url> ~/sites/docker-envs

# One-time setup: creates shared Docker volumes, verifies Docker and MySQL
dev setup

# (Optional) Pre-fetch base images for faster builds
dev pull

# (Optional) Pre-build all image combos to avoid build waits later
dev build-all
```

The `dev` script resolves paths relative to its own location. All projects are created as sibling directories under `~/sites/`.

## Usage

### WordPress Plugin Project

```bash
dev init wordpress my-plugin
cd ~/sites/my-plugin
dev up
```

What happens:
- Creates `~/sites/my-plugin/` with `.env` and `docker-compose.yml`
- Creates `wp_my_plugin` database on host MySQL
- On first `dev up`, the entrypoint downloads WordPress core, creates `wp-config.php`, installs WP, and activates your plugin
- Your plugin code is bind-mounted at `/var/www/html/wp-content/plugins/my-plugin`
- WordPress core is stored in a named volume (`my-plugin-wp-core`)

Admin URL: `http://localhost:<port>/wp-admin/` -- credentials: `admin` / `admin`

### Laravel Project

```bash
dev init laravel my-app
cd ~/sites/my-app
dev up
```

What happens:
- Creates `~/sites/my-app/` with `.env` and `docker-compose.yml`
- Creates `my_app` database on host MySQL
- On first `dev up`, runs `composer install` if `vendor/` is missing
- Your project root is bind-mounted at `/var/www/html`
- `vendor/` and `node_modules/` are stored in named volumes for performance

### Generic PHP Package

```bash
dev init package my-lib
cd ~/sites/my-lib
dev up
```

What happens:
- Creates `~/sites/my-lib/` with `.env` and `docker-compose.yml`
- No database is created (packages don't need one)
- No web server is started -- runs PHP-FPM only (`php-fpm -F`)
- Your project root is bind-mounted at `/var/www/html`

## Command Reference

### Setup

| Command | Description |
|---------|-------------|
| `dev setup` | One-time setup. Creates shared `dev_composer_cache` and `dev_npm_cache` Docker volumes, verifies Docker and MySQL are available. |
| `dev pull` | Pre-fetches all Alpine base images (PHP 7.4-8.4, nginx, composer) so builds skip network downloads. |
| `dev build-all` | Pre-builds all 12 image combinations (PHP 7.4-8.4 x nginx/apache). Tags as `devenv-php<version>-<server>`. |
| `dev init <type> <name>` | Bootstraps a new project. Types: `wordpress`, `laravel`, `package`. Creates directory, `.env`, `docker-compose.yml`, and database (if applicable). Auto-assigns the next available port starting from 8080. Project names must be lowercase letters, numbers, hyphens, or underscores only (max 50 chars). |

### Lifecycle

| Command | Description |
|---------|-------------|
| `dev up` | Builds image (if needed) and starts container in detached mode. Runs the entrypoint which handles WordPress download or Laravel composer install on first boot. |
| `dev down` | Stops and removes containers. Preserves volumes. |
| `dev clean` | Stops containers AND removes volumes (with confirmation prompt). Next `dev up` will re-download WordPress core / re-install vendor. |

### Development

| Command | Description |
|---------|-------------|
| `dev shell` | Opens a bash shell inside the `php` container. Also aliased as `dev ssh`. |
| `dev logs [-f]` | Shows container logs. Pass `-f` to follow. All extra args are forwarded to `docker compose logs`. |
| `dev wp <args>` | WP-CLI passthrough. Runs `wp --allow-root --path=/var/www/html <args>` inside the container. |
| `dev artisan <args>` | Laravel Artisan passthrough. Runs `php artisan <args>` inside the container. |
| `dev composer <args>` | Composer passthrough. Runs `composer <args>` inside the container. |
| `dev npm <args>` | npm passthrough. Runs `npm <args>` inside the container. |
| `dev seed` | Seeds the database. For WordPress: runs `seeds/seed.sh` from project root, or the base seed if none exists. For Laravel: runs `php artisan db:seed`. |

### Testing

| Command | Description |
|---------|-------------|
| `dev test [args]` | Runs Pest if installed, otherwise PHPUnit. All args are forwarded. |
| `dev lint [--fix]` | Runs PHPStan (if installed), then Pint in test mode. Pass `--fix` to let Pint auto-fix. |

### Switching

| Command | Description |
|---------|-------------|
| `dev php <version>` | Switches PHP version. Valid: `7.4`, `8.0`, `8.1`, `8.2`, `8.3`, `8.4`. Updates `.env` and rebuilds the container. |
| `dev web <server>` | Switches web server. Valid: `nginx`, `apache`. Updates `.env` and rebuilds the container. |
| `dev xdebug on` | Enables Xdebug in debug mode (step debugging). Reloads PHP-FPM via `kill -USR2`. Persists to `.env`. No container rebuild. |
| `dev xdebug off` | Disables Xdebug. Reloads PHP-FPM. Persists to `.env`. No container rebuild. |
| `dev xdebug coverage` | Enables Xdebug in coverage-only mode (for `--coverage` reports). Persists to `.env`. |
| `dev xdebug status` | Prints whether Xdebug is loaded and the current mode. |

### Info

| Command | Description |
|---------|-------------|
| `dev ps` | Lists all devenv projects across `~/sites/`, showing name, type, port, PHP version, and running status. |
| `dev status` | Shows current project config (type, PHP version, web server, port, database) and container status. |
| `dev help` | Prints the help screen. |

## Configuration

Each project gets a `.env` file with these variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `COMPOSE_PROJECT_NAME` | `<name>` | Docker Compose project name. Used for container naming. |
| `PROJECT_TYPE` | varies | `wordpress`, `laravel`, or `package`. Controls entrypoint behavior. |
| `PROJECT_ROOT` | `.` | Host path to the project source (relative to `.env` location). |
| `PHP_VERSION` | `8.3` | PHP version for the container image. |
| `WEB_SERVER` | `nginx` | Web server: `nginx` or `apache`. |
| `HTTP_PORT` | auto-assigned | Host port mapped to container port 80 (bound to `127.0.0.1` only). Starts at 8080, increments to find an open port. |
| `DB_NAME` | `wp_<name>` / `<name>` | Database name. WordPress projects are prefixed with `wp_`. Hyphens are converted to underscores. |
| `DB_USER` | `root` | MySQL user. |
| `DB_PASSWORD` | (empty) | MySQL password. |
| `DB_PORT` | `3306` | MySQL port on the host. |
| `REDIS_PORT` | `6379` | Redis port on the host. WordPress and Laravel only. |
| `WP_VERSION` | `latest` | WordPress core version to download. WordPress only. |
| `PLUGIN_SLUG` | `<name>` | Plugin directory name for bind mount. WordPress only. |
| `XDEBUG_MODE` | `off` | Initial Xdebug mode. Overridden at runtime by `dev xdebug`. |
| `HOST_UID` | `501` | macOS user UID. Matched inside the container for permission-free bind mounts. |

## Switching PHP Versions

```bash
dev php 8.2
```

This updates `PHP_VERSION` in `.env` and runs `docker compose up -d --build`, which rebuilds the container using the `devenv-php8.2-<server>` image. Your project files, database, and volumes are preserved.

Pre-build all images with `dev build-all` to make switching instant.

## Switching Web Servers

```bash
dev web apache
```

This updates `WEB_SERVER` in `.env` and rebuilds. The Dockerfile uses a multi-stage build where `server-nginx` and `server-apache` are separate stages. The final stage selects via `FROM server-${WEB_SERVER}`.

Both nginx and apache configs are mounted into every container. The entrypoint starts whichever server matches `WEB_SERVER`. Switching between them works via `dev web apache` or `dev web nginx`.

Each project type has both nginx and apache configs:
- `nginx/wordpress.conf` -- document root at `/var/www/html`
- `nginx/laravel.conf` -- document root at `/var/www/html/public`
- `apache/wordpress.conf` -- same, with `AllowOverride All` for `.htaccess`
- `apache/laravel.conf` -- same, pointing at `/public`

All web configs include security headers (`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`), gzip compression, upload directory PHP execution blocking (WordPress), and dotfile/sensitive file blocking.

## Xdebug

Xdebug is installed in all images but disabled by default. Toggle it at runtime without rebuilding:

```bash
dev xdebug on        # Step debugging
dev xdebug off       # Disable (better performance)
dev xdebug coverage  # Code coverage mode
dev xdebug status    # Check current state
```

The toggle writes a new INI file inside the container and sends `USR2` to PHP-FPM (found via `pgrep`) to reload configuration. No container restart needed. The current Xdebug mode is persisted to `.env` so it survives `dev down` / `dev up` cycles.

### VS Code Configuration

Create `.vscode/launch.json` in your project:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Listen for Xdebug",
            "type": "php",
            "request": "launch",
            "port": 9003,
            "pathMappings": {
                "/var/www/html/wp-content/plugins/<your-plugin>": "${workspaceFolder}"
            }
        }
    ]
}
```

For Laravel projects, change the path mapping to:

```json
{
    "/var/www/html": "${workspaceFolder}"
}
```

Settings used: `client_host=host.docker.internal`, `client_port=9003`, `start_with_request=yes`, `idekey=VSCODE`.

## Project Structure

```
docker-envs/
├── dev                     # CLI script -- all commands live here
├── Dockerfile              # Multi-stage: php-base → server-nginx/server-apache → final
├── entrypoint.sh           # Container startup: WP download, composer install, PHP-FPM + web server
├── compose/
│   ├── base.yml            # Reference only (unused). Each type.yml below is self-contained.
│   ├── wordpress.yml       # Self-contained WordPress Compose config (ports, volumes, healthcheck)
│   ├── laravel.yml         # Self-contained Laravel Compose config (ports, volumes, healthcheck)
│   └── package.yml         # Self-contained Package Compose config (no web server, php-fpm only)
├── templates/
│   ├── wordpress.env       # .env template for WordPress projects
│   ├── laravel.env         # .env template for Laravel projects
│   ├── package.env         # .env template for package projects
│   ├── docker-compose.wordpress.yml  # Thin docker-compose that includes compose/wordpress.yml
│   ├── docker-compose.laravel.yml    # Thin docker-compose that includes compose/laravel.yml
│   └── docker-compose.package.yml    # Thin docker-compose that includes compose/package.yml
├── nginx/
│   ├── wordpress.conf      # Nginx vhost for WordPress (root: /var/www/html)
│   └── laravel.conf        # Nginx vhost for Laravel (root: /var/www/html/public)
├── apache/
│   ├── wordpress.conf      # Apache vhost for WordPress
│   └── laravel.conf        # Apache vhost for Laravel
├── php/
│   ├── php.ini             # Custom PHP config (256M memory, 64M uploads, opcache, error logging)
│   ├── xdebug-on.ini       # Xdebug debug-mode config (reference)
│   └── xdebug-off.ini      # Xdebug disabled config (mounted by default)
├── seeds/
│   └── wordpress-base.sh   # Default WP seed: test users, categories, posts, pages, pretty permalinks
└── plugins/
    └── .gitkeep            # Placeholder for shared plugins
```

## How It Works

### Compose Include

Each project gets a one-line `docker-compose.yml`:

```yaml
include:
  - path: ../docker-envs/compose/wordpress.yml
```

This references the shared Compose config in `docker-envs/compose/`. Each type file (`wordpress.yml`, `laravel.yml`, `package.yml`) is fully self-contained -- it defines the complete service, volumes, ports, healthcheck, and environment. Projects include a single file and provide `.env` overrides. `base.yml` exists as a reference only and is not used by any project.

### Multi-Stage Dockerfile

```
php-base (php:X.Y-fpm-alpine)
  ├── system deps (git, node, npm, zip, icu, image libs)
  ├── PHP extensions (gd, intl, mbstring, mysqli, pdo_mysql, opcache, zip, bcmath, exif, soap)
  ├── Xdebug (version-aware: 3.1.6 for PHP 7.4, 3.3.2 for PHP 8.0, latest for 8.1+)
  ├── Redis extension
  ├── Composer 2
  ├── WP-CLI
  └── UID-matched www-data user
        │
        ├── server-nginx  (adds nginx)
        └── server-apache (adds apache2, mod_proxy_fcgi, mod_rewrite)
              │
              └── final (selected by WEB_SERVER build arg)
```

### Entrypoint Flow

1. **MySQL wait**: Waits up to 30 seconds for host MySQL to become reachable (WordPress and Laravel only)
2. **WordPress**: If the `.devenv-installed` sentinel file is missing, downloads WP core, creates `wp-config.php` (with debug constants), installs WP, and activates the plugin. On subsequent boots, detects WP version mismatch and logs a warning if installed version differs from `WP_VERSION`.
3. **Laravel**: If `vendor/autoload.php` is missing and `composer.json` exists, runs `composer install`
4. Fixes ownership (`chown www-data:www-data`) -- full recursive on first run, top-level only on warm starts (sentinel: `.chown-done`)
5. Creates `_health.php` healthcheck endpoint
6. Starts PHP-FPM in the background
7. Starts nginx or Apache in the foreground

### Host Networking

Containers reach host MySQL and Redis via `host.docker.internal` (mapped via `extra_hosts: host.docker.internal:host-gateway`). No database or cache containers are needed.

## WordPress Workflow

```bash
dev init wordpress my-plugin
cd ~/sites/my-plugin

# Start -- first run downloads WP core and installs
dev up

# Your plugin code is at ~/sites/my-plugin/ and mounted into WP
# Edit code on your host, changes reflect immediately

# WP-CLI
dev wp plugin list
dev wp option get siteurl
dev wp user list

# Seed test data (users, posts, categories, pages)
dev seed

# Run tests (requires phpunit/pest in your plugin's composer.json)
dev test

# Check logs
dev logs -f
```

### WordPress Details

- **Core storage**: Named volume `<project>-wp-core` at `/var/www/html`. Survives `dev down`, cleared by `dev clean`.
- **Plugin mount**: Your project directory is bind-mounted at `/var/www/html/wp-content/plugins/<plugin-slug>` with `:cached` for performance.
- **wp-config.php**: Auto-generated with `WP_DEBUG`, `WP_DEBUG_LOG`, `WP_DEBUG_DISPLAY`, `SCRIPT_DEBUG` all enabled. `FS_METHOD=direct`, `WP_MEMORY_LIMIT=256M`.
- **Admin credentials**: `admin` / `admin` (email: `dev@local.test`)
- **Permalinks**: Set to `/%postname%/` by the seed script.

### Base Seed Data

Running `dev seed` (without a project-level `seeds/seed.sh`) creates:
- 3 users: editor/editor, author/author, subscriber/subscriber
- 3 categories: News, Tutorials, Updates
- 10 test posts
- 2 pages: About, Contact
- Pretty permalink structure (`/%postname%/`)

## Laravel Workflow

```bash
dev init laravel my-app
cd ~/sites/my-app

# Start -- first run runs composer install
dev up

# Artisan commands
dev artisan migrate
dev artisan make:model Post -mfc
dev artisan tinker

# Composer
dev composer require laravel/sanctum

# npm / Vite
dev npm install
dev npm run dev

# Seed
dev seed          # runs php artisan db:seed

# Tests
dev test
dev lint --fix
```

### Laravel Details

- **Document root**: `/var/www/html/public` (both nginx and apache configs)
- **Vendor volume**: `<project>-vendor` -- persists `vendor/` in a named volume for performance
- **Node modules volume**: `<project>-node-modules` -- persists `node_modules/` similarly
- **Database**: Created on host MySQL as `<name>` (hyphens converted to underscores)

## Testing

```bash
# Run PHPUnit or Pest (auto-detected)
dev test

# Pass arguments through
dev test --filter=MyTest
dev test --coverage

# Enable coverage mode first for coverage reports
dev xdebug coverage
dev test --coverage-html=coverage
dev xdebug off

# Lint with PHPStan + Pint
dev lint          # test mode (no changes)
dev lint --fix    # auto-fix with Pint
```

## Troubleshooting

### Port Conflicts

`dev init` auto-assigns the next available port starting from 8080. If you get a port conflict on `dev up`:

```bash
# Check what's using the port
lsof -iTCP:8080 -sTCP:LISTEN

# Change the port in .env
# HTTP_PORT=8081

dev down && dev up
```

### MySQL Connection Refused

The container connects to MySQL on your host via `host.docker.internal:3306`.

- Ensure MySQL is running (check DBngin)
- Ensure MySQL allows connections from `root` without a password, or set `DB_PASSWORD` in `.env`
- Test from the container: `dev shell` then `mysql -h host.docker.internal -u root`

The `dev` CLI auto-detects DBngin sockets when running host-side MySQL commands (e.g., `dev setup`, `dev init`). It checks `/tmp/mysql_3306.sock` and `/tmp/mysql.sock` if a TCP connection fails.

### Permission Issues

The Dockerfile creates a `www-data` user with your macOS UID (default 501). If files are owned by root:

```bash
# Check your UID
id -u

# If not 501, update .env and rebuild
# HOST_UID=<your-uid>
dev down && dev up
```

### Slow First Build

The first `dev up` builds the Docker image (installing PHP extensions, Xdebug, etc.). This takes 2-5 minutes. Pre-build all images to avoid this:

```bash
dev build-all
```

### WordPress Core Re-download

WordPress core lives in a named volume. To force a fresh download:

```bash
dev clean    # removes all volumes including wp-core
dev up       # re-downloads everything
```

### Container Won't Start

```bash
# Check logs for the error
dev logs

# Common: entrypoint.sh not found or not executable
# The entrypoint is bind-mounted from docker-envs/entrypoint.sh
# Ensure the file exists and docker-envs is at ~/sites/docker-envs
```

## Building All Images

```bash
dev build-all
```

Builds 12 images covering every PHP version and web server combination:

| Image Tag | PHP | Server |
|-----------|-----|--------|
| `devenv-php7.4-nginx` | 7.4 | nginx |
| `devenv-php7.4-apache` | 7.4 | apache |
| `devenv-php8.0-nginx` | 8.0 | nginx |
| `devenv-php8.0-apache` | 8.0 | apache |
| `devenv-php8.1-nginx` | 8.1 | nginx |
| `devenv-php8.1-apache` | 8.1 | apache |
| `devenv-php8.2-nginx` | 8.2 | nginx |
| `devenv-php8.2-apache` | 8.2 | apache |
| `devenv-php8.3-nginx` | 8.3 | nginx |
| `devenv-php8.3-apache` | 8.3 | apache |
| `devenv-php8.4-nginx` | 8.4 | nginx |
| `devenv-php8.4-apache` | 8.4 | apache |

Pre-building makes `dev php <version>` and `dev web <server>` switches near-instant since the image already exists locally.

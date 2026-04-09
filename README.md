# docker-envs

> A `dev` CLI and shared Docker base that bootstraps WordPress plugin, Laravel/Filament, and generic PHP development environments on macOS.

## Features

- Single multi-stage Dockerfile supporting PHP 7.4, 8.0, 8.1, 8.2, 8.3, and 8.4
- Nginx and Apache web server variants, switchable without rebuild
- HTTPS on every project via shared mkcert certificate (trusted in browser, no warnings)
- All PHP mail routed to host Mailhog — one inbox for all projects
- Per-project thin `docker-compose.yml` using Compose `include` to reference shared configs
- Host-side MySQL and Redis via DBngin (no database containers)
- `dev` CLI wrapping all Docker Compose operations
- Xdebug toggle (debug, coverage, off) without container rebuild
- Shared Composer and npm cache volumes across all projects
- Automatic WordPress core download, install, and plugin activation on first run
- Automatic `composer install` for Laravel projects on first run
- WordPress test data seeding via WP-CLI
- UID mapping for permission-free bind mounts on macOS
- Security hardened: localhost-only ports, security headers, gzip, upload PHP blocking

## Prerequisites

- **macOS** (uses `host.docker.internal` for host networking)
- **Docker Desktop** or **OrbStack** with Docker Compose v2.20+
- **MySQL** running on the host (port 3306) — [DBngin](https://dbngin.com/) recommended
- **Redis** running on the host (port 6379) — optional, for Laravel/WordPress object cache
- **mkcert** — `brew install mkcert` (for HTTPS)
- **Mailhog** — `brew install mailhog` (for email capture)
- Root-accessible MySQL (`mysql -u root` without password)

## Quick Start

```bash
# 1. Clone into your sites directory
git clone https://github.com/unaibamir/docker-devenv.git ~/sites/docker-envs

# 2. Add dev to PATH
echo 'export PATH="$HOME/sites/docker-envs:$PATH"' >> ~/.zshrc && source ~/.zshrc

# 3. One-time setup (volumes, check deps)
dev setup

# 4. Generate shared HTTPS certificate
dev secure

# 5. (Optional) Pre-fetch base images for faster builds
dev pull

# 6. Create a WordPress plugin project
dev init wordpress my-plugin

# 7. Start it
cd ~/sites/my-plugin && dev up
```

Your site is now at:
- `http://localhost:8080`
- `https://localhost:8443` (trusted cert, no browser warning)

Admin: `http://localhost:8080/wp-admin/` — `admin` / `admin`

All outgoing email captured at `http://localhost:8025` (Mailhog).

## Installation

```bash
# Clone into your sites directory (projects are created as siblings)
git clone https://github.com/unaibamir/docker-devenv.git ~/sites/docker-envs

# Add to PATH (add to your .zshrc or .bashrc)
export PATH="$HOME/sites/docker-envs:$PATH"

# One-time setup: creates shared Docker volumes, verifies Docker, MySQL, and Mailhog
dev setup

# Generate shared HTTPS cert (run once — valid until 2028, shared by all projects)
dev secure

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
- Auto-assigns HTTP port (from 8080) and HTTPS port (from 8443)
- On first `dev up`: downloads WordPress core, creates `wp-config.php`, installs WP, activates your plugin
- Your plugin code is bind-mounted at `/var/www/html/wp-content/plugins/my-plugin`
- WordPress core is stored in a named volume (`my-plugin-wp-core`)

Admin URL: `http://localhost:<port>/wp-admin/` — credentials: `admin` / `admin`

### Laravel Project

```bash
dev init laravel my-app
cd ~/sites/my-app
dev up
```

What happens:
- Creates `~/sites/my-app/` with `.env` and `docker-compose.yml`
- Creates `my_app` database on host MySQL
- On first `dev up`: runs `composer install` if `vendor/` is missing
- Your project root is bind-mounted at `/var/www/html`
- `vendor/` and `node_modules/` stored in named volumes for performance

### Generic PHP Package

```bash
dev init package my-lib
cd ~/sites/my-lib
dev up
```

What happens:
- Creates `~/sites/my-lib/` with `.env` and `docker-compose.yml`
- No database created (packages don't need one)
- No web server — runs PHP-FPM only (`php-fpm -F`)
- Your project root is bind-mounted at `/var/www/html`

## Command Reference

### Setup

| Command | Description |
|---------|-------------|
| `dev setup` | One-time setup. Creates shared cache volumes, verifies Docker, MySQL, and Mailhog are running. |
| `dev secure [--renew]` | Generates a shared mkcert HTTPS certificate for `localhost`, `127.0.0.1`, `::1`. Run once — all projects share it. `--renew` regenerates. |
| `dev pull` | Pre-fetches all Alpine base images (PHP 7.4-8.4, nginx, composer) so builds skip network downloads. |
| `dev build-all` | Pre-builds all 12 image combinations (PHP 7.4-8.4 × nginx/apache). Tags as `devenv-php<version>-<server>`. |
| `dev init <type> <name>` | Bootstraps a new project. Types: `wordpress`, `laravel`, `package`. Creates directory, `.env`, `docker-compose.yml`, and database (if applicable). Auto-assigns HTTP and HTTPS ports. Project names: lowercase, numbers, hyphens, underscores (max 50 chars). |

### Lifecycle

| Command | Description |
|---------|-------------|
| `dev up` | Builds image (if needed) and starts container. Runs entrypoint which handles WordPress download or Laravel composer install on first boot. |
| `dev down` | Stops and removes containers. Preserves volumes. |
| `dev clean` | Stops containers AND removes volumes (confirmation prompt). Next `dev up` re-downloads WordPress core / re-installs vendor. |

### Development

| Command | Description |
|---------|-------------|
| `dev shell` | Opens a bash shell inside the container. Also aliased as `dev ssh`. |
| `dev logs [-f]` | Shows container logs. Pass `-f` to follow. |
| `dev wp <args>` | WP-CLI passthrough. Runs `wp --allow-root --path=/var/www/html <args>` inside the container. |
| `dev artisan <args>` | Laravel Artisan passthrough. Runs `php artisan <args>` inside the container. |
| `dev composer <args>` | Composer passthrough. Runs `composer <args>` inside the container. |
| `dev npm <args>` | npm passthrough. Runs `npm <args>` inside the container. |
| `dev seed` | Seeds the database. WordPress: runs `seeds/seed.sh` or the base seed. Laravel: runs `php artisan db:seed`. |

### Testing

| Command | Description |
|---------|-------------|
| `dev test [args]` | Runs Pest if installed, otherwise PHPUnit. All args forwarded. |
| `dev lint [--fix]` | Runs PHPStan (if installed), then Pint in test mode. `--fix` to auto-fix. |

### Switching

| Command | Description |
|---------|-------------|
| `dev php <version>` | Switches PHP version. Valid: `7.4`, `8.0`, `8.1`, `8.2`, `8.3`, `8.4`. Updates `.env` and rebuilds. |
| `dev web <server>` | Switches web server. Valid: `nginx`, `apache`. Updates `.env` and rebuilds. |
| `dev xdebug on` | Enables Xdebug in debug mode. Reloads PHP-FPM via `pgrep`. Persists to `.env`. No rebuild. |
| `dev xdebug off` | Disables Xdebug. Reloads PHP-FPM. Persists to `.env`. No rebuild. |
| `dev xdebug coverage` | Enables Xdebug in coverage-only mode. Persists to `.env`. |
| `dev xdebug status` | Prints whether Xdebug is loaded and the current mode. |

### Info

| Command | Description |
|---------|-------------|
| `dev ps` | Lists all devenv projects across `~/sites/`, showing name, type, port, PHP version, and running status. |
| `dev status` | Shows current project config (type, PHP version, web server, ports, database) and container status. |
| `dev help` | Prints the help screen. |

### Mail

| Command | Description |
|---------|-------------|
| `dev mailhog` | Opens Mailhog web UI at `http://localhost:8025`. All PHP mail from all containers is captured here. |

## Configuration

Each project gets a `.env` file with these variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `COMPOSE_PROJECT_NAME` | `<name>` | Docker Compose project name. Used for container and volume naming. |
| `PROJECT_TYPE` | varies | `wordpress`, `laravel`, or `package`. Controls entrypoint behavior. |
| `PROJECT_ROOT` | `.` | Host path to project source (relative to `.env` location). |
| `PHP_VERSION` | `8.3` | PHP version for the container image. |
| `WEB_SERVER` | `nginx` | Web server: `nginx` or `apache`. |
| `HTTP_PORT` | auto-assigned | Host port mapped to container port 80 (bound to `127.0.0.1`). Starts at 8080. |
| `HTTPS_PORT` | auto-assigned | Host port mapped to container port 443 (bound to `127.0.0.1`). Starts at 8443. |
| `DB_NAME` | `wp_<name>` / `<name>` | Database name. WordPress prefixed with `wp_`. Hyphens converted to underscores. |
| `DB_USER` | `root` | MySQL user. |
| `DB_PASSWORD` | (empty) | MySQL password. |
| `DB_PORT` | `3306` | MySQL port on the host. |
| `REDIS_PORT` | `6379` | Redis port on the host. WordPress and Laravel only. |
| `WP_VERSION` | `latest` | WordPress core version to download. WordPress only. |
| `PLUGIN_SLUG` | `<name>` | Plugin directory name for bind mount. WordPress only. |
| `XDEBUG_MODE` | `off` | Xdebug mode. Persisted by `dev xdebug on/off/coverage`. |
| `HOST_UID` | `501` | macOS user UID. Matched inside container for permission-free bind mounts. |
| `MAILHOG_HOST` | `host.docker.internal` | SMTP relay host for PHP mail (Mailhog). |

## HTTPS

Every project gets HTTPS via a single shared mkcert certificate. Run once:

```bash
dev secure
```

This generates `certs/localhost.pem` and `certs/localhost-key.pem` covering `localhost`, `127.0.0.1`, and `::1`. All projects use this shared cert — no per-project generation needed.

Each project exposes port 443 via `HTTPS_PORT` (auto-assigned, default 8443):

```
http://localhost:8080   # HTTP
https://localhost:8443  # HTTPS (trusted, no browser warning)
```

To regenerate (e.g., after expiry in 2028):

```bash
dev secure --renew
```

The `certs/` directory is gitignored. Run `dev secure` on any new machine.

## Email — Mailhog

All PHP mail from all containers is automatically captured by Mailhog running on your host. No SMTP configuration needed in your application — `mail()`, Laravel `Mail::`, WordPress `wp_mail()` all work out of the box.

```bash
# Start Mailhog if not already running
mailhog &

# View captured emails in browser
dev mailhog        # opens http://localhost:8025
```

**How it works:** `msmtp` is installed in every container and configured as PHP's `sendmail_path`. It relays all outgoing mail to `host.docker.internal:1025` (Mailhog's SMTP port). No emails escape to the internet — everything is captured locally.

**One inbox for all projects.** All containers from all projects send to the same Mailhog instance.

`dev setup` checks that Mailhog is running on port 1025.

## Switching PHP Versions

```bash
dev php 8.2
```

Updates `PHP_VERSION` in `.env` and runs `docker compose up -d --build`. Your project files, database, and volumes are preserved.

Pre-build all images with `dev build-all` to make switching instant (no rebuild wait).

## Switching Web Servers

```bash
dev web apache
```

Updates `WEB_SERVER` in `.env` and rebuilds. Both nginx and Apache configs are mounted into every container — the entrypoint starts whichever matches `WEB_SERVER`.

Configs per project type:
- `nginx/wordpress.conf` — root at `/var/www/html`, WP rewrites
- `nginx/laravel.conf` — root at `/var/www/html/public`, front controller
- `apache/wordpress.conf` — `AllowOverride All` for `.htaccess`
- `apache/laravel.conf` — same, pointing at `/public`

All configs include: security headers, gzip, HSTS on HTTPS, upload PHP blocking (WordPress), dotfile/sensitive file blocking, FastCGI tuning.

## Xdebug

Installed in all images but disabled by default. Toggle at runtime without rebuilding:

```bash
dev xdebug on        # Step debugging (port 9003)
dev xdebug off       # Disable (better performance)
dev xdebug coverage  # Code coverage mode
dev xdebug status    # Check current state
```

State persists to `.env` — survives `dev down` / `dev up`.

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

For Laravel, use `"/var/www/html": "${workspaceFolder}"` as the path mapping.

Settings: `client_host=host.docker.internal`, `client_port=9003`, `start_with_request=yes`, `idekey=VSCODE`.

## Project Structure

```
docker-envs/
├── dev                     # CLI script — all commands
├── Dockerfile              # Multi-stage: php-base → server-nginx/server-apache → final
├── entrypoint.sh           # Container startup: MySQL wait, WP/Laravel setup, FPM + web server
├── certs/                  # mkcert certificates (gitignored, run 'dev secure' to generate)
│   ├── localhost.pem
│   └── localhost-key.pem
├── compose/
│   ├── base.yml            # Reference only (unused — each type.yml is self-contained)
│   ├── wordpress.yml       # WordPress: ports, volumes, HTTPS, Mailhog, healthcheck
│   ├── laravel.yml         # Laravel: ports, volumes, HTTPS, Mailhog, healthcheck
│   └── package.yml         # Package: php-fpm only, no web server
├── templates/
│   ├── wordpress.env       # .env template for WordPress projects
│   ├── laravel.env         # .env template for Laravel projects
│   ├── package.env         # .env template for package projects
│   ├── docker-compose.wordpress.yml
│   ├── docker-compose.laravel.yml
│   └── docker-compose.package.yml
├── nginx/
│   ├── wordpress.conf      # HTTP + HTTPS server blocks for WordPress
│   └── laravel.conf        # HTTP + HTTPS server blocks for Laravel
├── apache/
│   ├── wordpress.conf      # HTTP + HTTPS VirtualHosts for WordPress
│   └── laravel.conf        # HTTP + HTTPS VirtualHosts for Laravel
├── php/
│   ├── php.ini             # 256M memory, 64M uploads, opcache, msmtp sendmail_path
│   ├── msmtp.conf          # msmtp relay config → host.docker.internal:1025 (Mailhog)
│   ├── xdebug-on.ini       # Xdebug debug-mode config (reference)
│   └── xdebug-off.ini      # Xdebug disabled (mounted by default)
├── seeds/
│   └── wordpress-base.sh   # WP seed: test users, categories, posts, pages
└── plugins/
    └── .gitkeep            # Placeholder for shared local plugins
```

## How It Works

### Compose Include

Each project gets a one-line `docker-compose.yml`:

```yaml
include:
  - path: ../docker-envs/compose/wordpress.yml
```

Each type file (`wordpress.yml`, `laravel.yml`, `package.yml`) is fully self-contained — defines the complete service, volumes, ports, healthcheck, and environment. `base.yml` is a reference only.

### Multi-Stage Dockerfile

```
php-base (php:X.Y-fpm-alpine)
  ├── system deps (git, node, npm, msmtp, msmtp-mta, zip, icu, image libs)
  ├── PHP extensions (gd, intl, mbstring, mysqli, pdo_mysql, opcache, zip, bcmath, exif, soap)
  ├── Xdebug (version-aware: 3.1.6 for PHP 7.4, 3.3.2 for PHP 8.0, latest for 8.1+)
  ├── Redis extension
  ├── Composer 2
  ├── WP-CLI (with SHA-512 checksum verification)
  └── UID-matched www-data user (macOS UID 501)
        │
        ├── server-nginx  (adds nginx)
        └── server-apache (adds apache2, apache2-ssl, mod_proxy_fcgi, mod_ssl, mod_headers)
              │
              └── final (selected by WEB_SERVER build arg)
```

Build deps (`$PHPIZE_DEPS`) are removed after extension compilation — saves ~170MB per image.

### Entrypoint Flow

1. **MySQL wait** — polls `host.docker.internal:3306` via PDO, up to 30 seconds
2. **WordPress** — if `.devenv-installed` sentinel is missing: downloads WP core, creates `wp-config.php` (WP_DEBUG, WP_DEBUG_LOG, SCRIPT_DEBUG, FS_METHOD=direct), installs WP, activates plugin. Tracks installed version in `.wp-version`, warns on mismatch
3. **Laravel** — if `composer.json` exists and `vendor/autoload.php` is missing: runs `composer install`
4. **Ownership** — `chown -R` on first run only (sentinel `.chown-done`), top-level only on warm starts
5. **Healthcheck** — creates `_health.php` at webroot
6. **Package mode** — if `PROJECT_TYPE=package`, starts `php-fpm -F` and exits (no web server)
7. **PHP-FPM** — starts in background
8. **Web server** — nginx or Apache starts in foreground (keeps container alive)

### Host Networking

Containers reach host MySQL, Redis, and Mailhog via `host.docker.internal` (mapped via `extra_hosts: host.docker.internal:host-gateway`). No database or mail containers needed.

### Mail Routing

`msmtp` is installed as PHP's sendmail replacement. All mail is relayed to `host.docker.internal:1025` (Mailhog SMTP). Configuration in `php/msmtp.conf`.

## WordPress Workflow

```bash
dev init wordpress my-plugin
cd ~/sites/my-plugin && dev up

# WP-CLI
dev wp plugin list
dev wp user list
dev wp option get siteurl

# Seed test data
dev seed

# Activate a dependency plugin
dev wp plugin install woocommerce --activate

# Check emails sent by plugin
dev mailhog

# Tests
dev test
dev logs -f
```

### WordPress Details

- **Core storage**: Named volume `<project>-wp-core`. Survives `dev down`, cleared by `dev clean`.
- **Plugin mount**: Project directory bind-mounted at `/var/www/html/wp-content/plugins/<slug>`
- **wp-config.php**: Auto-generated with `WP_DEBUG`, `WP_DEBUG_LOG`, `WP_DEBUG_DISPLAY`, `SCRIPT_DEBUG`. `FS_METHOD=direct`, `WP_MEMORY_LIMIT=256M`
- **Admin credentials**: `admin` / `admin` (email: `dev@local.test`)
- **WP version pinning**: Set `WP_VERSION=6.5` in `.env`. Changing it warns on next start — run `dev wp core update` or `dev clean && dev up` to apply

### Base Seed Data

`dev seed` (without `seeds/seed.sh`) creates:
- 3 users: editor/editor, author/author, subscriber/subscriber
- 3 categories: News, Tutorials, Updates
- 10 test posts
- 2 pages: About, Contact
- Pretty permalink structure (`/%postname%/`)

## Laravel Workflow

```bash
dev init laravel my-app
cd ~/sites/my-app && dev up

# Artisan
dev artisan migrate
dev artisan make:model Post -mfc
dev artisan tinker

# Composer
dev composer require laravel/sanctum

# npm / Vite
dev npm install
dev npm run dev       # Vite dev server on port 5173

# Seed
dev seed              # runs php artisan db:seed

# Check emails
dev mailhog

# Tests
dev test
dev lint --fix
```

### Laravel Details

- **Document root**: `/var/www/html/public` (nginx and apache)
- **Vendor volume**: `<project>-vendor` — `vendor/` persisted in named volume for macOS performance
- **Node modules volume**: `<project>-node-modules` — same for `node_modules/`
- **Database**: Created on host MySQL as `<name>` (underscores replacing hyphens)
- **CORS headers**: Laravel nginx/apache configs include `Access-Control-Allow-Origin: *` for Vite HMR

## Testing

```bash
# Run PHPUnit or Pest (auto-detected from composer.json)
dev test

# Pass arguments
dev test --filter=MyTest
dev test --coverage

# Enable Xdebug coverage mode first
dev xdebug coverage
dev test --coverage-html=coverage
dev xdebug off

# Lint with PHPStan + Pint
dev lint          # test mode (no changes)
dev lint --fix    # auto-fix with Pint
```

## Troubleshooting

### Port Conflicts

`dev init` auto-assigns the next available HTTP and HTTPS ports (starting at 8080 and 8443). If you get a port conflict on `dev up`:

```bash
# Check what's using the port
lsof -iTCP:8080 -sTCP:LISTEN

# Change ports in .env
# HTTP_PORT=8082
# HTTPS_PORT=8445

dev down && dev up
```

### MySQL Connection Refused

The container connects to MySQL via `host.docker.internal:3306`. `dev setup` and `dev init` use the host `mysql` client, auto-detecting DBngin sockets at `/tmp/mysql_3306.sock` and `/tmp/mysql.sock` when TCP fails.

```bash
# Test from inside the container
dev shell
mysql -h host.docker.internal -u root
```

### Mailhog Not Running

```bash
# Start Mailhog
mailhog &

# Verify
dev setup   # should show "Mailhog SMTP: OK (port 1025)"
```

If Mailhog isn't running, PHP `mail()` calls will silently fail (msmtp can't connect to port 1025).

### HTTPS Certificate Issues

```bash
# Regenerate the cert
dev secure --renew

# Check mkcert CA is installed in your browser/keychain
mkcert -install

# Verify cert covers localhost
openssl x509 -in ~/sites/docker-envs/certs/localhost.pem -text -noout | grep -A1 "Subject Alternative"
```

### Permission Issues

The Dockerfile creates a `www-data` user matching your macOS UID (default 501). If files are owned by root:

```bash
id -u   # check your UID, update HOST_UID in .env if different
dev down && dev up
```

### Slow First Build

First `dev up` builds the image (~2-5 min). Pre-fetch and pre-build to avoid this:

```bash
dev pull       # pulls base images
dev build-all  # builds all 12 combos
```

### WordPress Core Re-download

```bash
dev clean   # removes wp-core volume
dev up      # re-downloads WordPress
```

### Container Won't Start

```bash
dev logs    # check error output

# Common: entrypoint bind mount path issue
# Ensure docker-envs is at ~/sites/docker-envs
ls ~/sites/docker-envs/entrypoint.sh
```

## Building All Images

```bash
dev build-all
```

Builds 12 images covering every PHP version and web server combination:

| Image Tag | PHP | Server |
|-----------|-----|--------|
| `devenv-php7.4-nginx` | 7.4 | nginx |
| `devenv-php7.4-apache` | 7.4 | Apache |
| `devenv-php8.0-nginx` | 8.0 | nginx |
| `devenv-php8.0-apache` | 8.0 | Apache |
| `devenv-php8.1-nginx` | 8.1 | nginx |
| `devenv-php8.1-apache` | 8.1 | Apache |
| `devenv-php8.2-nginx` | 8.2 | nginx |
| `devenv-php8.2-apache` | 8.2 | Apache |
| `devenv-php8.3-nginx` | 8.3 | nginx |
| `devenv-php8.3-apache` | 8.3 | Apache |
| `devenv-php8.4-nginx` | 8.4 | nginx |
| `devenv-php8.4-apache` | 8.4 | Apache |

Pre-building makes `dev php <version>` and `dev web <server>` switches near-instant.

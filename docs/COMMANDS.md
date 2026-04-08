# `dev` Command Reference

## Setup (run once or when needed)

| Command | What it does |
|---|---|
| `dev setup` | Creates shared Docker cache volumes (`dev_composer_cache`, `dev_npm_cache`), verifies Docker and MySQL are running. Run once on a fresh machine. |
| `dev pull` | Pre-fetches all Alpine base images (`php:7.4-fpm-alpine` through `php:8.4-fpm-alpine`, `composer:2`, `nginx:alpine`). Run once so builds skip network downloads. |
| `dev build-all` | Builds all 12 image combos (6 PHP versions x 2 web servers). Run if you want instant PHP/server switching with zero build wait. |
| `dev init <type> <name>` | Creates a new project at `~/sites/<name>/` with `.env` and `docker-compose.yml`. Types: `wordpress`, `laravel`, `package`. Auto-assigns next free port starting at 8080, creates MySQL database. |

## Lifecycle (daily use)

| Command | What it does |
|---|---|
| `dev up` | Builds image if needed, starts the container. On first run for WordPress: downloads WP core, creates wp-config, installs WP, activates your plugin. For Laravel: runs `composer install` if vendor/ is missing. |
| `dev down` | Stops and removes container. Keeps volumes (WP core, vendor, databases stay intact). |
| `dev clean` | Stops container AND deletes all volumes. Next `dev up` starts completely fresh -- re-downloads WP, re-installs vendor. Use when things are broken. |

## Development (while working)

| Command | What it does |
|---|---|
| `dev shell` | Opens a bash shell inside the container. Also works as `dev ssh`. |
| `dev logs [-f]` | Shows container logs. `-f` to follow live. |
| `dev wp <args>` | Runs WP-CLI inside the container. Example: `dev wp plugin list`, `dev wp user create foo foo@test.com --role=editor --user_pass=foo` |
| `dev artisan <args>` | Runs Laravel Artisan. Example: `dev artisan migrate`, `dev artisan make:model Post -m` |
| `dev composer <args>` | Runs Composer. Example: `dev composer require spatie/laravel-permission` |
| `dev npm <args>` | Runs npm. Example: `dev npm install`, `dev npm run build` |
| `dev seed` | Seeds test data. WordPress: creates 3 users, 3 categories, 10 posts, 2 pages. Laravel: runs `php artisan db:seed`. |

## Testing

| Command | What it does |
|---|---|
| `dev test [args]` | Runs Pest if installed, otherwise PHPUnit. Args pass through: `dev test --filter=MyTest` |
| `dev lint [--fix]` | Runs PHPStan then Pint in test mode. `--fix` lets Pint auto-fix code style. |

## Switching (change stack without losing data)

| Command | What it does |
|---|---|
| `dev php <version>` | Switches PHP version. Valid: `7.4`, `8.0`, `8.1`, `8.2`, `8.3`, `8.4`. Rebuilds container, keeps your data. |
| `dev web <server>` | Switches web server. Valid: `nginx`, `apache`. Rebuilds container. |
| `dev xdebug on` | Enables step debugging. Connects to IDE on port 9003. No rebuild -- takes ~1 second. |
| `dev xdebug off` | Disables Xdebug for better performance. |
| `dev xdebug coverage` | Enables coverage mode for `--coverage` reports. |
| `dev xdebug status` | Shows if Xdebug is loaded and current mode. |

## Info

| Command | What it does |
|---|---|
| `dev ps` | Lists all devenv projects across `~/sites/` with name, type, port, PHP version, running status. |
| `dev status` | Shows current project's config and whether the container is running. |
| `dev help` | Prints the help screen. |

## Typical Workflow

```bash
# First time setup
dev setup && dev pull

# Start a WordPress plugin project
dev init wordpress my-plugin
cd ~/sites/my-plugin
dev up                          # site at localhost:8080, admin/admin

# Work on it
dev wp plugin list
dev seed
dev xdebug on                   # when you need to debug
dev test                        # run tests
dev php 8.2                     # test on older PHP

# Done for the day
dev down
```

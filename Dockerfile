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

FROM php:8.4-apache

ENV DEBIAN_FRONTEND=noninteractive

# System deps for GD, intl, zip, bz2, imagick and build tools for PECL
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       libzip-dev libpng-dev libjpeg-dev libwebp-dev libfreetype6-dev libicu-dev zlib1g-dev libonig-dev libbz2-dev \
       git unzip autoconf gcc make pkg-config libmagickwand-dev imagemagick ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) bcmath gd intl pdo_mysql zip bz2 opcache

# install uploadprogress via PECL if available
RUN pecl install uploadprogress || true \
    && docker-php-ext-enable uploadprogress || true

# Install Composer (v2)
RUN php -r "copy('https://getcomposer.org/installer','/tmp/composer-setup.php');" \
    && php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --version=2.6.5 \
    && rm /tmp/composer-setup.php

# Apache: use /app/web as document root
RUN a2enmod rewrite \
    && sed -i 's#/var/www/html#/app/web#g' /etc/apache2/sites-available/000-default.conf /etc/apache2/apache2.conf || true

# Apache: allow serving Drupal docroot outside /var/www
RUN printf '%s\n' \
    '<Directory /app/web>' \
    '  Options FollowSymLinks' \
    '  AllowOverride All' \
    '  Require all granted' \
    '</Directory>' \
    > /etc/apache2/conf-available/app-web.conf \
    && a2enconf app-web

WORKDIR /app/web

# Create app dir and set permissive ownership (will be overridden by mounts)
RUN mkdir -p /app/web && chown -R www-data:www-data /app

CMD ["apache2-foreground"]

ARG DRUPAL_BASE_IMAGE=php:8.4.18-fpm-bookworm
FROM ${DRUPAL_BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git unzip curl ca-certificates gnupg dirmngr \
       libzip-dev libpng-dev libjpeg62-turbo-dev libwebp-dev libfreetype6-dev \
       libicu-dev libpq-dev libonig-dev libxml2-dev libbz2-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" \
       bcmath bz2 exif gd intl mysqli opcache pdo_mysql pdo_pgsql zip

RUN pecl install uploadprogress redis \
    && docker-php-ext-enable uploadprogress redis opcache

RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php composer-setup.php --install-dir=/usr/local/bin --filename=composer \
    && rm composer-setup.php

COPY docker/drupal-fpm/container-entrypoint.sh /usr/local/bin/container-entrypoint.sh
COPY docker/drupal-fpm/update-check.sh /usr/local/bin/update-check.sh
RUN chmod +x /usr/local/bin/container-entrypoint.sh /usr/local/bin/update-check.sh

WORKDIR /var/www/html
ENTRYPOINT ["/usr/local/bin/container-entrypoint.sh"]
CMD ["php-fpm"]

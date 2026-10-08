#!/bin/sh
# wordpress entrypoint script

set -e

WP_PATH="/var/www/html"

MYSQL_PASSWORD="$(cat /run/secrets/db_password)"
WP_ADMIN_PASSWORD="$(cat /run/secrets/wp_admin_password)"
WP_USER_PASSWORD="$(cat /run/secrets/wp_user_password)"


echo "------------------ Checking if wordpress files are installed... ------------------"

if [ ! -f "$WP_PATH/wp-config.php" ]; then
echo "------------------ Not Found: downloading - creating - installing ------------------"

        echo "INSIDE CONDITINO"
        wp core download --path="$WP_PATH" --allow-root

        wp config create \
        --path="$WP_PATH" \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${MYSQL_PASSWORD}" \
        --dbhost=mariadb \
        --allow-root

        wp core install \
        --path="$WP_PATH" \
        --url="https://${DOMAIN_NAME}" \
        --title="Inception" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --allow-root

        wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --user_pass="${WP_USER_PASSWORD}" \
        --role=author \
        --path="$WP_PATH" \
        --allow-root
echo "------------------ Download - creation - installation succeeded ------------------"
fi

echo "------------------ php-fpm is listening... ------------------"

exec php-fpm8.2 -F
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

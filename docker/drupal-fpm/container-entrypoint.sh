#!/usr/bin/env bash
set -euo pipefail

policy="${UPDATE_POLICY:-off}"
target="${UPDATE_TARGET:-system}"
writable_uid="${WRITABLE_UID:-33}"
writable_gid="${WRITABLE_GID:-33}"
writable_dir_mode="${WRITABLE_DIR_MODE:-2775}"
writable_file_mode="${WRITABLE_FILE_MODE:-0664}"

for writable_dir in \
  /var/www/html/web/sites/default/files \
  /var/www/html/web/sites/default/private \
  /tmp/drupal; do
  mkdir -p "${writable_dir}"
  chown -R "${writable_uid}:${writable_gid}" "${writable_dir}" || true
  find "${writable_dir}" -type d -exec chmod "${writable_dir_mode}" {} + || true
  find "${writable_dir}" -type f -exec chmod "${writable_file_mode}" {} + || true
done

if [[ "${policy}" != "off" ]]; then
  /usr/local/bin/update-check.sh "${policy}" "${target}" || true
fi

exec docker-php-entrypoint "$@"

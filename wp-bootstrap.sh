#!/bin/bash
# wp-bootstrap.sh : finalise sti-wp01 (nginx + php-fpm + WordPress).
# Lancé par cloud-init (runcmd) une fois les paquets installés.
# Idempotent : peut être rejoué sans rien casser (WordPress n'est téléchargé
# qu'une fois, wp-content n'est jamais écrasé, wp-config.php est régénéré).
# Usage : wp-bootstrap.sh <version-wordpress>
set -euo pipefail

WP_VERSION="${1:?usage: wp-bootstrap.sh <version-wordpress>}"
STAGE=/opt/wp-provision
WEBROOT=/var/www/wordpress
TARBALL="wordpress-${WP_VERSION}.tar.gz"

log() { echo "[wp-bootstrap] $*"; }

# --- 1. php-fpm : service et socket dépendent de la version de PHP installée --
# (déduite du binaire php-fpm réellement présent : php-fpm8.2, php-fpm8.4...)
shopt -s nullglob
fpm_bins=(/usr/sbin/php-fpm[0-9]*)
[ "${#fpm_bins[@]}" -gt 0 ] || { echo "[wp-bootstrap] php-fpm introuvable" >&2; exit 1; }
PHP_V="${fpm_bins[-1]##*php-fpm}"
PHP_FPM_SOCK="/run/php/php${PHP_V}-fpm.sock"
log "PHP ${PHP_V}"
systemctl enable --now "php${PHP_V}-fpm"

# --- 2. WordPress (téléchargé une seule fois, intégrité vérifiée en SHA1) -----
install -d -o www-data -g www-data -m 0755 "${WEBROOT}"
if [ ! -f "${WEBROOT}/wp-includes/version.php" ]; then
    log "Téléchargement de WordPress ${WP_VERSION}"
    TMP="$(mktemp -d)"
    trap 'rm -rf "${TMP}"' EXIT
    curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused \
        -o "${TMP}/${TARBALL}" "https://wordpress.org/${TARBALL}"
    SHA1="$(curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused \
        "https://wordpress.org/${TARBALL}.sha1")"
    echo "${SHA1}  ${TMP}/${TARBALL}" | sha1sum -c -
    tar -xzf "${TMP}/${TARBALL}" -C "${WEBROOT}" --strip-components=1
else
    log "WordPress déjà présent, téléchargement ignoré"
fi
chown -R www-data:www-data "${WEBROOT}"

# --- 3. wp-config.php (préparé par Terraform, contient le mot de passe de la base)
install -o root -g www-data -m 0640 "${STAGE}/wp-config.php" "${WEBROOT}/wp-config.php"

# --- 4. nginx ----------------------------------------------------------------
sed "s#__PHP_FPM_SOCK__#${PHP_FPM_SOCK}#" "${STAGE}/nginx-wordpress.conf" \
    > /etc/nginx/sites-available/wordpress
ln -sfn /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/wordpress
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl reload-or-restart nginx

# --- 5. Contrôle : nginx répond-il ? -----------------------------------------
code=000
for _ in $(seq 1 15); do
    code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/healthz || true)"
    [ "${code}" = "200" ] && break
    sleep 1
done
log "GET /healthz -> HTTP ${code}"
[ "${code}" = "200" ]
log "sti-wp01 prêt : en attente de MariaDB (sti-db01) et d'HAProxy"

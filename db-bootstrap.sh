#!/bin/bash
# db-bootstrap.sh : finalise sti-db01 (MariaDB partagée par les nœuds WordPress).
# Lancé par cloud-init (runcmd) une fois mariadb-server installé.
# Idempotent : rejouable sans rien casser (mot de passe resynchronisé, comptes
# non autorisés supprimés).
set -euo pipefail

STAGE=/opt/db-provision
CONF=/etc/mysql/mariadb.conf.d/99-sti.cnf

log() { echo "[db-bootstrap] $*"; }

# DB_NAME, DB_USER, DB_PASSWORD, ALLOWED_HOSTS (valeurs validées par Terraform)
# shellcheck source=/dev/null
. "${STAGE}/db.env"

# --- 1. Configuration : écoute réseau, pas de résolution DNS inverse ----------
systemctl enable --now mariadb
if ! cmp -s "${STAGE}/mariadb-sti.cnf" "${CONF}"; then
    install -o root -g root -m 0644 "${STAGE}/mariadb-sti.cnf" "${CONF}"
    systemctl restart mariadb
fi

# --- 2. Attente du serveur (root local, authentification par socket unix) -----
for _ in $(seq 1 30); do
    mariadb -e 'SELECT 1' >/dev/null 2>&1 && break
    sleep 1
done
mariadb -e 'SELECT 1' >/dev/null

# --- 3. Base et compte WordPress, limités aux réseaux autorisés (VLAN web) ----
# Le SQL passe par l'entrée standard : le mot de passe n'apparaît pas dans ps.
{
    echo "DROP DATABASE IF EXISTS test;"
    echo "DROP USER IF EXISTS ''@'localhost';"
    echo "DROP USER IF EXISTS ''@'$(hostname)';"
    echo "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    for h in ${ALLOWED_HOSTS}; do
        echo "CREATE USER IF NOT EXISTS '${DB_USER}'@'${h}' IDENTIFIED BY '${DB_PASSWORD}';"
        echo "ALTER USER '${DB_USER}'@'${h}' IDENTIFIED BY '${DB_PASSWORD}';"
        echo "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${h}';"
    done
    echo "FLUSH PRIVILEGES;"
} | mariadb

# --- 4. Convergence : retire les accès qui ne sont plus autorisés --------------
for h in $(mariadb -N -B -e "SELECT host FROM mysql.user WHERE user='${DB_USER}'"); do
    case " ${ALLOWED_HOSTS} " in
        *" ${h} "*) ;;
        *)
            log "suppression de ${DB_USER}@${h} (source non autorisée)"
            mariadb -e "DROP USER '${DB_USER}'@'${h}'"
            ;;
    esac
done

# --- 5. Contrôle : MariaDB écoute-t-elle sur le réseau (pas seulement en local) ? -
# Écoute limitée à 127.0.0.1 = cause n°1 de « Error establishing a database
# connection » côté WordPress : on échoue ici plutôt que de le découvrir plus tard.
listen=$(ss -H -ltn 'sport = :3306' | awk '{print $4}')
case "${listen}" in
    *0.0.0.0:3306* | *'*:3306'* | *'[::]:3306'*) ;;
    *)
        echo "[db-bootstrap] MariaDB n'écoute pas sur le réseau (3306) : '${listen:-rien}'" >&2
        exit 1
        ;;
esac
log "MariaDB écoute sur 3306 ; base ${DB_NAME}, compte ${DB_USER} autorisé depuis : ${ALLOWED_HOSTS}"

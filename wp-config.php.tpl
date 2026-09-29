<?php
/**
 * wp-config.php de sti-wp01 : généré par Terraform (wp-config.php.tpl), ne pas éditer à la main.
 *
 * - Base de données PARTAGÉE (sti-db01) : aucune base locale sur ce nœud.
 * - Clés et sels identiques sur tous les nœuds WordPress.
 * - Fonctionne derrière HAProxy (URL et HTTPS déduits des en-têtes de la requête).
 */

// --- Base de données (MariaDB partagée) ------------------------------------
define( 'DB_NAME',     '${db_name}' );
define( 'DB_USER',     '${db_user}' );
define( 'DB_PASSWORD', '${db_password}' );
define( 'DB_HOST',     '${db_host}' );
define( 'DB_CHARSET',  'utf8mb4' );
define( 'DB_COLLATE',  '' );

// --- Clés et sels d'authentification ---------------------------------------
// Doivent être IDENTIQUES sur sti-wp01 et sti-wp02 : sinon, avec le round-robin
// d'HAProxy, une session ouverte sur un nœud est invalide sur l'autre.
${salts}

$table_prefix = 'wp_';

define( 'WP_DEBUG', false );

// --- Derrière HAProxy -------------------------------------------------------
// HTTPS terminé sur le load balancer : HAProxy doit envoyer X-Forwarded-Proto.
// (En-tête à n'accepter que depuis HAProxy : voir les règles OPNsense.)
if ( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && 'https' === $_SERVER['HTTP_X_FORWARDED_PROTO'] ) {
	$_SERVER['HTTPS'] = 'on';
}

// URL du site déduite de la requête : le même nœud répond correctement en accès
// direct (http://IP-du-nœud) et via HAProxy (http://IP-ou-nom-du-LB).
if ( isset( $_SERVER['HTTP_HOST'] ) ) {
	$wp_scheme = ( ! empty( $_SERVER['HTTPS'] ) && 'off' !== $_SERVER['HTTPS'] ) ? 'https' : 'http';
	define( 'WP_HOME',    $wp_scheme . '://' . $_SERVER['HTTP_HOST'] );
	define( 'WP_SITEURL', $wp_scheme . '://' . $_SERVER['HTTP_HOST'] );
}

if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';

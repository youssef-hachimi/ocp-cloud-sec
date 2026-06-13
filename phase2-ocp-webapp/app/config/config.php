<?php
/**
 * OCP - Operations Control Panel
 * Configuration File
 * 
 * NOTE: For production, load sensitive values from environment variables
 * or HashiCorp Vault (Phase 4 integration)
 */

// Prevent direct access
if (!defined('OCP_ROOT')) {
    define('OCP_ROOT', dirname(__DIR__));
}

// =============================================================================
// DATABASE CONFIGURATION
// =============================================================================
// These values should be loaded from environment variables or Vault in production
define('DB_HOST', getenv('DB_HOST') ?: 'localhost');
define('DB_PORT', getenv('DB_PORT') ?: '3306');
define('DB_NAME', getenv('DB_NAME') ?: 'ocp_db');
define('DB_USER', getenv('DB_USER') ?: 'ocp_user');
define('DB_PASS', getenv('DB_PASS') ?: 'ocp_password_change_me');
define('DB_CHARSET', 'utf8mb4');

// =============================================================================
// APPLICATION SETTINGS
// =============================================================================
define('APP_NAME', 'Operations Control Panel');
define('APP_VERSION', '2.1.0');
define('APP_ENV', getenv('APP_ENV') ?: 'production'); // development | staging | production

// URL Configuration (for Phase 3 - Custom Domain)
define('BASE_URL', getenv('BASE_URL') ?: '/');
define('APP_URL', getenv('APP_URL') ?: 'https://app.yourdomain.com');

// =============================================================================
// SECURITY SETTINGS
// =============================================================================
define('SESSION_LIFETIME', 3600);           // 1 hour session
define('MAX_LOGIN_ATTEMPTS', 5);            // Lockout after 5 failed attempts
define('LOCKOUT_DURATION', 900);            // 15 minute lockout
define('PASSWORD_MIN_LENGTH', 8);
define('CSRF_TOKEN_NAME', 'ocp_csrf_token');

// HashiCorp Vault Integration (Phase 4)
define('VAULT_ENABLED', filter_var(getenv('VAULT_ENABLED') ?: 'false', FILTER_VALIDATE_BOOLEAN));
define('VAULT_ADDR', getenv('VAULT_ADDR') ?: 'http://vault.yourdomain.com:8200');
define('VAULT_ROLE_ID', getenv('VAULT_ROLE_ID') ?: '');
define('VAULT_SECRET_ID', getenv('VAULT_SECRET_ID') ?: '');
define('VAULT_DB_PATH', getenv('VAULT_DB_PATH') ?: 'secret/ocp/database');

// =============================================================================
// LOGGING
// =============================================================================
define('LOG_LEVEL', getenv('LOG_LEVEL') ?: 'INFO'); // DEBUG | INFO | WARNING | ERROR
define('LOG_FILE', OCP_ROOT . '/logs/ocp.log');
define('AUDIT_LOG_FILE', OCP_ROOT . '/logs/audit.log');

// =============================================================================
// ERROR HANDLING
// =============================================================================
if (APP_ENV === 'development') {
    error_reporting(E_ALL);
    ini_set('display_errors', '1');
} else {
    error_reporting(0);
    ini_set('display_errors', '0');
    ini_set('log_errors', '1');
    ini_set('error_log', OCP_ROOT . '/logs/php_errors.log');
}

// =============================================================================
// TIMEZONE
// =============================================================================
date_default_timezone_set('UTC');

// =============================================================================
// AUTOLOADER
// =============================================================================
spl_autoload_register(function ($class) {
    $prefix = 'OCP\\';
    $baseDir = OCP_ROOT . '/src/';
    
    $len = strlen($prefix);
    if (strncmp($prefix, $class, $len) !== 0) {
        return;
    }
    
    $relativeClass = substr($class, $len);
    $file = $baseDir . str_replace('\\', '/', $relativeClass) . '.php';
    
    if (file_exists($file)) {
        require $file;
    }
});

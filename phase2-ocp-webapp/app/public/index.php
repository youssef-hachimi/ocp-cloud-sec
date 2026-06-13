<?php
/**
 * OCP - Operations Control Panel
 * Main entry point - redirects to login or dashboard
 */

require_once __DIR__ . '/../config/config.php';
require_once __DIR__ . '/../src/utils/Database.php';
require_once __DIR__ . '/../src/utils/Security.php';
require_once __DIR__ . '/../src/utils/Logger.php';
require_once __DIR__ . '/../src/utils/Auth.php';

// Start session securely
Security::initSession();

$auth = new Auth();
$logger = new Logger();

// Check if user is authenticated
if ($auth->isAuthenticated()) {
    // Log the access
    $logger->info('User accessed dashboard', [
        'user' => $auth->getCurrentUser()['username'] ?? 'unknown',
        'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown'
    ]);
    
    // Include dashboard
    require_once __DIR__ . '/../src/views/dashboard.php';
} else {
    // Not authenticated, show login page
    require_once __DIR__ . '/../src/views/login.php';
}

<?php
/**
 * OCP API - Ping Utility Endpoint
 * 
 * WARNING: This endpoint is INTENTIONALLY VULNERABLE to command injection.
 * Used for security testing demonstration.
 */

require_once __DIR__ . '/../../config/config.php';

header('Content-Type: application/json');

$host = $_GET['host'] ?? $_POST['ip'] ?? '127.0.0.1';
$count = intval($_GET['count'] ?? '4');

// Vulnerable: user input passed directly to shell command
// This allows command injection via: host=8.8.8.8;whoami
$cmd = "ping -c $count " . $host;

$output = [];
$returnCode = 0;
exec($cmd . " 2>&1", $output, $returnCode);

// Log for SIEM detection
$logger = new Logger();
$logger->info('Ping API called', ['host' => $host, 'ip' => $_SERVER['REMOTE_ADDR']]);

echo json_encode([
    'host' => $host,
    'command' => $cmd,
    'output' => implode("\n", $output),
    'return_code' => $returnCode
]);

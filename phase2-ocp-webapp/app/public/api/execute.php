<?php
/**
 * OCP API - Command Execution Endpoint
 * 
 * WARNING: This endpoint is INTENTIONALLY VULNERABLE for security testing.
 * It allows command injection for demonstrating SIEM/IDS detection.
 * 
 * DO NOT USE IN PRODUCTION WITHOUT PROPER SANITIZATION.
 */

require_once __DIR__ . '/../../config/config.php';

header('Content-Type: application/json');

$logger = new Logger();
$logger->info('API /execute accessed', ['ip' => $_SERVER['REMOTE_ADDR']]);

// Vulnerable to command injection - deliberately for testing
$cmd = $_GET['cmd'] ?? $_POST['command'] ?? '';

if (empty($cmd)) {
    http_response_code(400);
    echo json_encode(['error' => 'No command provided', 'usage' => 'GET /api/execute?cmd=<command>']);
    exit;
}

// Log the attempt (this will trigger Wazuh alerts)
$logger->warning('Command execution attempt', ['command' => $cmd, 'ip' => $_SERVER['REMOTE_ADDR']]);

// INSECURE: Direct command execution (vulnerable to injection)
$output = [];
$returnCode = 0;
exec($cmd . " 2>&1", $output, $returnCode);

echo json_encode([
    'command' => $cmd,
    'output' => implode("\n", $output),
    'return_code' => $returnCode,
    'executed_at' => date('Y-m-d H:i:s'),
    'warning' => 'This endpoint is for testing only - vulnerable to command injection'
], JSON_PRETTY_PRINT);

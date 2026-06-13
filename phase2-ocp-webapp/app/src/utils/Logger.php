<?php
/**
 * OCP Logger
 * Structured logging for application events and security audit trail
 */

class Logger
{
    private string $logFile;
    private string $auditFile;
    private string $minLevel;
    
    private array $levels = [
        'DEBUG' => 0,
        'INFO' => 1,
        'WARNING' => 2,
        'ERROR' => 3,
        'CRITICAL' => 4
    ];
    
    public function __construct()
    {
        $this->logFile = LOG_FILE;
        $this->auditFile = AUDIT_LOG_FILE;
        $this->minLevel = LOG_LEVEL;
        
        // Ensure log directory exists
        $logDir = dirname($this->logFile);
        if (!is_dir($logDir)) {
            mkdir($logDir, 0750, true);
        }
    }
    
    /**
     * Write log entry
     */
    private function write(string $level, string $message, array $context = []): void
    {
        if ($this->levels[$level] < ($this->levels[$this->minLevel] ?? 1)) {
            return;
        }
        
        $entry = [
            'timestamp' => date('Y-m-d H:i:s.u T'),
            'level' => $level,
            'message' => $message,
            'context' => array_merge($context, [
                'request_id' => $_SESSION['request_id'] ?? uniqid('req_', true),
                'ip' => Security::getClientIp(),
                'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? 'unknown',
                'method' => $_SERVER['REQUEST_METHOD'] ?? 'CLI',
                'uri' => $_SERVER['REQUEST_URI'] ?? 'unknown'
            ])
        ];
        
        $logLine = json_encode($entry, JSON_UNESCAPED_SLASHES) . PHP_EOL;
        
        // Write to main log
        error_log($logLine, 3, $this->logFile);
        
        // Write WARNING and above to audit log
        if ($this->levels[$level] >= $this->levels['WARNING']) {
            error_log($logLine, 3, $this->auditFile);
        }
    }
    
    public function debug(string $message, array $context = []): void
    {
        $this->write('DEBUG', $message, $context);
    }
    
    public function info(string $message, array $context = []): void
    {
        $this->write('INFO', $message, $context);
    }
    
    public function warning(string $message, array $context = []): void
    {
        $this->write('WARNING', $message, $context);
    }
    
    public function error(string $message, array $context = []): void
    {
        $this->write('ERROR', $message, $context);
    }
    
    public function critical(string $message, array $context = []): void
    {
        $this->write('CRITICAL', $message, $context);
    }
    
    /**
     * Log security audit event (always logged regardless of level)
     */
    public function audit(string $action, array $details = []): void
    {
        $entry = [
            'timestamp' => date('Y-m-d H:i:s.u T'),
            'type' => 'AUDIT',
            'action' => $action,
            'user_id' => $_SESSION['user_id'] ?? null,
            'username' => $_SESSION['username'] ?? 'anonymous',
            'ip' => Security::getClientIp(),
            'details' => $details
        ];
        
        $logLine = json_encode($entry, JSON_UNESCAPED_SLASHES) . PHP_EOL;
        error_log($logLine, 3, $this->auditFile);
    }
}

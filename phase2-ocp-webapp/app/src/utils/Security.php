<?php
/**
 * OCP Security Utilities
 * CSRF protection, input validation, output encoding, session management
 */

class Security
{
    /**
     * Initialize secure session
     */
    public static function initSession(): void
    {
        if (session_status() === PHP_SESSION_NONE) {
            // Secure session cookie settings
            ini_set('session.cookie_httponly', '1');
            ini_set('session.cookie_secure', '1');
            ini_set('session.cookie_samesite', 'Strict');
            ini_set('session.use_strict_mode', '1');
            ini_set('session.gc_maxlifetime', SESSION_LIFETIME);
            
            session_start();
            
            // Regenerate session ID periodically to prevent fixation
            if (!isset($_SESSION['created'])) {
                $_SESSION['created'] = time();
            } else if (time() - $_SESSION['created'] > 1800) {
                session_regenerate_id(true);
                $_SESSION['created'] = time();
            }
            
            // Validate session
            if (isset($_SESSION['last_activity']) && (time() - $_SESSION['last_activity'] > SESSION_LIFETIME)) {
                // Session expired
                session_unset();
                session_destroy();
                session_start();
            }
            
            $_SESSION['last_activity'] = time();
            
            // Bind session to IP (optional security measure)
            if (!isset($_SESSION['ip_address'])) {
                $_SESSION['ip_address'] = $_SERVER['REMOTE_ADDR'] ?? null;
            } else if ($_SESSION['ip_address'] !== ($_SERVER['REMOTE_ADDR'] ?? null)) {
                // IP mismatch - possible session hijacking
                session_unset();
                session_destroy();
                session_start();
            }
        }
    }
    
    /**
     * Generate CSRF token
     */
    public static function generateToken(): string
    {
        if (empty($_SESSION[CSRF_TOKEN_NAME])) {
            $_SESSION[CSRF_TOKEN_NAME] = bin2hex(random_bytes(32));
        }
        return $_SESSION[CSRF_TOKEN_NAME];
    }
    
    /**
     * Validate CSRF token
     */
    public static function validateToken(?string $token): bool
    {
        if (empty($token) || empty($_SESSION[CSRF_TOKEN_NAME])) {
            return false;
        }
        return hash_equals($_SESSION[CSRF_TOKEN_NAME], $token);
    }
    
    /**
     * Get CSRF token HTML input field
     */
    public static function csrfField(): string
    {
        $token = self::generateToken();
        return '<input type="hidden" name="' . CSRF_TOKEN_NAME . '" value="' . htmlspecialchars($token) . '">';
    }
    
    /**
     * Sanitize user input
     */
    public static function sanitize(string $input): string
    {
        return htmlspecialchars(strip_tags(trim($input)), ENT_QUOTES, 'UTF-8');
    }
    
    /**
     * Validate email format
     */
    public static function validateEmail(string $email): bool
    {
        return filter_var($email, FILTER_VALIDATE_EMAIL) !== false;
    }
    
    /**
     * Validate password strength
     */
    public static function validatePassword(string $password): array
    {
        $errors = [];
        
        if (strlen($password) < PASSWORD_MIN_LENGTH) {
            $errors[] = "Password must be at least " . PASSWORD_MIN_LENGTH . " characters";
        }
        if (!preg_match('/[A-Z]/', $password)) {
            $errors[] = "Password must contain at least one uppercase letter";
        }
        if (!preg_match('/[a-z]/', $password)) {
            $errors[] = "Password must contain at least one lowercase letter";
        }
        if (!preg_match('/[0-9]/', $password)) {
            $errors[] = "Password must contain at least one number";
        }
        if (!preg_match('/[!@#$%^&*(),.?":{}|<>]/', $password)) {
            $errors[] = "Password must contain at least one special character";
        }
        
        return $errors;
    }
    
    /**
     * Hash password securely
     */
    public static function hashPassword(string $password): string
    {
        return password_hash($password, PASSWORD_ARGON2ID, [
            'memory_cost' => 65536,
            'time_cost' => 4,
            'threads' => 3
        ]);
    }
    
    /**
     * Verify password
     */
    public static function verifyPassword(string $password, string $hash): bool
    {
        return password_verify($password, $hash);
    }
    
    /**
     * Generate secure random token
     */
    public static function generateSecureToken(int $length = 32): string
    {
        return bin2hex(random_bytes($length));
    }
    
    /**
     * Rate limiting check
     */
    public static function checkRateLimit(string $key, int $maxAttempts = 5, int $windowSeconds = 300): bool
    {
        $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
        $rateKey = "rate_limit_{$key}_{$ip}";
        
        if (!isset($_SESSION[$rateKey])) {
            $_SESSION[$rateKey] = [
                'attempts' => 1,
                'first_attempt' => time()
            ];
            return true;
        }
        
        $data = &$_SESSION[$rateKey];
        
        // Reset if window has passed
        if (time() - $data['first_attempt'] > $windowSeconds) {
            $data['attempts'] = 1;
            $data['first_attempt'] = time();
            return true;
        }
        
        $data['attempts']++;
        
        if ($data['attempts'] > $maxAttempts) {
            return false; // Rate limited
        }
        
        return true;
    }
    
    /**
     * Get client IP address (respecting proxies)
     */
    public static function getClientIp(): string
    {
        $headers = ['HTTP_CF_CONNECTING_IP', 'HTTP_X_FORWARDED_FOR', 'HTTP_X_FORWARDED', 
                    'HTTP_X_CLUSTER_CLIENT_IP', 'HTTP_FORWARDED_FOR', 'HTTP_FORWARDED', 'REMOTE_ADDR'];
        
        foreach ($headers as $header) {
            if (!empty($_SERVER[$header])) {
                $ips = explode(',', $_SERVER[$header]);
                $ip = trim($ips[0]);
                if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) {
                    return $ip;
                }
            }
        }
        
        return $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    }
    
    /**
     * Security headers helper
     */
    public static function setSecurityHeaders(): void
    {
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('X-XSS-Protection: 1; mode=block');
        header('Referrer-Policy: strict-origin-when-cross-origin');
        header("Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'");
        header('Permissions-Policy: geolocation=(), microphone=(), camera=()');
    }
    
    /**
     * Log security event
     */
    public static function logEvent(string $event, array $context = []): void
    {
        $logger = new Logger();
        $logger->warning("Security Event: $event", array_merge($context, [
            'ip' => self::getClientIp(),
            'uri' => $_SERVER['REQUEST_URI'] ?? 'unknown',
            'method' => $_SERVER['REQUEST_METHOD'] ?? 'unknown'
        ]));
    }
}

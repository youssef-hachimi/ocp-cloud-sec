<?php
/**
 * OCP Authentication Manager
 * Handles user login, logout, session management
 */

class Auth
{
    private Database $db;
    private Logger $logger;
    
    public function __construct()
    {
        $this->db = new Database();
        $this->logger = new Logger();
    }
    
    /**
     * Check if user is authenticated
     */
    public function isAuthenticated(): bool
    {
        return isset($_SESSION['user_id']) && !empty($_SESSION['user_id']);
    }
    
    /**
     * Get current user data
     */
    public function getCurrentUser(): ?array
    {
        if (!$this->isAuthenticated()) {
            return null;
        }
        
        // Return cached user data from session
        return [
            'id' => $_SESSION['user_id'],
            'username' => $_SESSION['username'] ?? '',
            'email' => $_SESSION['email'] ?? '',
            'role' => $_SESSION['role'] ?? 'user',
            'display_name' => $_SESSION['display_name'] ?? $_SESSION['username'] ?? 'User'
        ];
    }
    
    /**
     * Check if current user has admin role
     */
    public function isAdmin(): bool
    {
        $user = $this->getCurrentUser();
        return $user !== null && ($user['role'] === 'admin' || $user['role'] === 'superadmin');
    }
    
    /**
     * Login user with credentials
     */
    public function login(string $username, string $password): array
    {
        // Check rate limiting
        if (!Security::checkRateLimit('login', MAX_LOGIN_ATTEMPTS, LOCKOUT_DURATION)) {
            $this->logger->warning('Login rate limit exceeded', [
                'username' => $username,
                'ip' => Security::getClientIp()
            ]);
            return ['success' => false, 'error' => 'Too many login attempts. Please try again later.'];
        }
        
        // Validate inputs
        if (empty($username) || empty($password)) {
            return ['success' => false, 'error' => 'Username and password are required.'];
        }
        
        // Find user by username or email
        $users = Database::query(
            "SELECT id, username, email, password_hash, display_name, role, status, failed_attempts, locked_until 
             FROM users 
             WHERE username = ? OR email = ? 
             LIMIT 1",
            [$username, $username]
        );
        
        if (empty($users)) {
            // Log failed attempt without revealing user doesn't exist
            $this->logger->warning('Failed login attempt - user not found', [
                'username' => $username,
                'ip' => Security::getClientIp()
            ]);
            return ['success' => false, 'error' => 'Invalid username or password.'];
        }
        
        $user = $users[0];
        
        // Check if account is locked
        if ($user['locked_until'] && strtotime($user['locked_until']) > time()) {
            $remaining = ceil((strtotime($user['locked_until']) - time()) / 60);
            return ['success' => false, 'error' => "Account locked. Try again in $remaining minutes."];
        }
        
        // Check if account is active
        if ($user['status'] !== 'active') {
            return ['success' => false, 'error' => 'Account is not active. Please contact administrator.'];
        }
        
        // Verify password
        if (!Security::verifyPassword($password, $user['password_hash'])) {
            // Increment failed attempts
            $newAttempts = ($user['failed_attempts'] ?? 0) + 1;
            $lockUntil = null;
            
            if ($newAttempts >= MAX_LOGIN_ATTEMPTS) {
                $lockUntil = date('Y-m-d H:i:s', time() + LOCKOUT_DURATION);
            }
            
            Database::execute(
                "UPDATE users SET failed_attempts = ?, locked_until = ? WHERE id = ?",
                [$newAttempts, $lockUntil, $user['id']]
            );
            
            $this->logger->warning('Failed login attempt - wrong password', [
                'username' => $username,
                'ip' => Security::getClientIp(),
                'attempt' => $newAttempts
            ]);
            
            return ['success' => false, 'error' => 'Invalid username or password.'];
        }
        
        // Successful login - reset failed attempts
        Database::execute(
            "UPDATE users SET failed_attempts = 0, locked_until = NULL, last_login = NOW() WHERE id = ?",
            [$user['id']]
        );
        
        // Set session
        $_SESSION['user_id'] = $user['id'];
        $_SESSION['username'] = $user['username'];
        $_SESSION['email'] = $user['email'];
        $_SESSION['role'] = $user['role'];
        $_SESSION['display_name'] = $user['display_name'];
        $_SESSION['login_time'] = time();
        
        // Log successful login
        $this->logger->info('User logged in successfully', [
            'user_id' => $user['id'],
            'username' => $user['username'],
            'ip' => Security::getClientIp(),
            'role' => $user['role']
        ]);
        
        return ['success' => true, 'user' => $this->getCurrentUser()];
    }
    
    /**
     * Logout current user
     */
    public function logout(): void
    {
        $user = $this->getCurrentUser();
        
        if ($user) {
            $this->logger->info('User logged out', [
                'user_id' => $user['id'],
                'username' => $user['username']
            ]);
        }
        
        // Clear session
        $_SESSION = [];
        
        if (ini_get('session.use_cookies')) {
            $params = session_get_cookie_params();
            setcookie(
                session_name(),
                '',
                [
                    'expires' => time() - 42000,
                    'path' => $params['path'],
                    'domain' => $params['domain'],
                    'secure' => $params['secure'],
                    'httponly' => $params['httponly'],
                    'samesite' => 'Strict'
                ]
            );
        }
        
        session_destroy();
    }
    
    /**
     * Require authentication - redirect if not logged in
     */
    public function requireAuth(): void
    {
        if (!$this->isAuthenticated()) {
            header('Location: ' . BASE_URL . 'login.php');
            exit;
        }
    }
    
    /**
     * Require admin role
     */
    public function requireAdmin(): void
    {
        $this->requireAuth();
        
        if (!$this->isAdmin()) {
            http_response_code(403);
            die('Access denied. Admin privileges required.');
        }
    }
    
    /**
     * Register new user
     */
    public function register(string $username, string $email, string $password, string $displayName = ''): array
    {
        // Validate inputs
        if (empty($username) || empty($email) || empty($password)) {
            return ['success' => false, 'error' => 'All fields are required.'];
        }
        
        if (!Security::validateEmail($email)) {
            return ['success' => false, 'error' => 'Invalid email format.'];
        }
        
        $pwErrors = Security::validatePassword($password);
        if (!empty($pwErrors)) {
            return ['success' => false, 'error' => implode(' ', $pwErrors)];
        }
        
        // Check if username/email already exists
        $existing = Database::query(
            "SELECT id FROM users WHERE username = ? OR email = ? LIMIT 1",
            [$username, $email]
        );
        
        if (!empty($existing)) {
            return ['success' => false, 'error' => 'Username or email already exists.'];
        }
        
        // Hash password
        $passwordHash = Security::hashPassword($password);
        
        // Insert user
        try {
            Database::execute(
                "INSERT INTO users (username, email, password_hash, display_name, role, status, created_at) 
                 VALUES (?, ?, ?, ?, 'user', 'active', NOW())",
                [$username, $email, $passwordHash, $displayName ?: $username]
            );
            
            $userId = Database::lastInsertId();
            
            $this->logger->info('New user registered', [
                'user_id' => $userId,
                'username' => $username
            ]);
            
            return ['success' => true, 'user_id' => $userId];
        } catch (Exception $e) {
            $this->logger->error('Registration failed', ['error' => $e->getMessage()]);
            return ['success' => false, 'error' => 'Registration failed. Please try again.'];
        }
    }
}

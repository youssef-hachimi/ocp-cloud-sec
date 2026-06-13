<?php
/**
 * OCP Login Page
 */

// Prevent direct access
if (!defined('OCP_ROOT')) {
    define('OCP_ROOT', dirname(__DIR__, 2));
}

require_once OCP_ROOT . '/config/config.php';

$auth = new Auth();
$logger = new Logger();
$error = '';
$success = '';

// Handle login form submission
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Validate CSRF token
    if (!Security::validateToken($_POST[CSRF_TOKEN_NAME] ?? null)) {
        $error = 'Invalid security token. Please refresh the page and try again.';
        Security::logEvent('CSRF validation failed', ['ip' => Security::getClientIp()]);
    } else {
        $username = $_POST['username'] ?? '';
        $password = $_POST['password'] ?? '';
        $remember = isset($_POST['remember']);
        
        $result = $auth->login($username, $password);
        
        if ($result['success']) {
            $logger->audit('user_login_success', ['username' => $username]);
            
            // Set remember me cookie if requested
            if ($remember) {
                $token = Security::generateSecureToken(32);
                // In production, store token hash in database with expiry
                setcookie('remember', $token, [
                    'expires' => time() + 30 * 24 * 3600,
                    'path' => '/',
                    'secure' => true,
                    'httponly' => true,
                    'samesite' => 'Strict'
                ]);
            }
            
            header('Location: ' . BASE_URL . 'index.php');
            exit;
        } else {
            $error = $result['error'];
            $logger->audit('user_login_failed', ['username' => $username, 'reason' => $error]);
        }
    }
}

// Handle logout message
if (isset($_GET['logout']) && $_GET['logout'] === 'success') {
    $success = 'You have been successfully logged out.';
}

Security::setSecurityHeaders();
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - <?php echo Security::sanitize(APP_NAME); ?></title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .login-container {
            background: #ffffff;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            width: 100%;
            max-width: 420px;
            padding: 40px;
        }
        
        .login-header {
            text-align: center;
            margin-bottom: 30px;
        }
        
        .login-header .logo {
            width: 64px;
            height: 64px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 16px;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 16px;
            color: white;
            font-size: 28px;
            font-weight: bold;
        }
        
        .login-header h1 {
            color: #1a1a2e;
            font-size: 24px;
            font-weight: 700;
        }
        
        .login-header p {
            color: #6b7280;
            font-size: 14px;
            margin-top: 4px;
        }
        
        .alert {
            padding: 12px 16px;
            border-radius: 8px;
            margin-bottom: 20px;
            font-size: 14px;
        }
        
        .alert-error {
            background: #fef2f2;
            color: #dc2626;
            border: 1px solid #fecaca;
        }
        
        .alert-success {
            background: #f0fdf4;
            color: #16a34a;
            border: 1px solid #bbf7d0;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-group label {
            display: block;
            color: #374151;
            font-size: 14px;
            font-weight: 500;
            margin-bottom: 6px;
        }
        
        .form-group input {
            width: 100%;
            padding: 12px 16px;
            border: 1px solid #d1d5db;
            border-radius: 8px;
            font-size: 14px;
            transition: border-color 0.2s, box-shadow 0.2s;
        }
        
        .form-group input:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        
        .form-options {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 24px;
            font-size: 13px;
        }
        
        .form-options label {
            display: flex;
            align-items: center;
            gap: 6px;
            color: #4b5563;
            cursor: pointer;
        }
        
        .form-options a {
            color: #667eea;
            text-decoration: none;
        }
        
        .form-options a:hover {
            text-decoration: underline;
        }
        
        .btn-login {
            width: 100%;
            padding: 14px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 15px;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        
        .btn-login:hover {
            transform: translateY(-1px);
            box-shadow: 0 8px 20px rgba(102, 126, 234, 0.3);
        }
        
        .btn-login:active {
            transform: translateY(0);
        }
        
        .login-footer {
            text-align: center;
            margin-top: 24px;
            padding-top: 24px;
            border-top: 1px solid #e5e7eb;
            color: #6b7280;
            font-size: 13px;
        }
        
        .login-footer a {
            color: #667eea;
            text-decoration: none;
            font-weight: 500;
        }
        
        .version-info {
            text-align: center;
            margin-top: 12px;
            color: #9ca3af;
            font-size: 11px;
        }
    </style>
</head>
<body>
    <div class="login-container">
        <div class="login-header">
            <div class="logo">OCP</div>
            <h1><?php echo Security::sanitize(APP_NAME); ?></h1>
            <p>Sign in to your account</p>
        </div>
        
        <?php if ($error): ?>
            <div class="alert alert-error"><?php echo Security::sanitize($error); ?></div>
        <?php endif; ?>
        
        <?php if ($success): ?>
            <div class="alert alert-success"><?php echo Security::sanitize($success); ?></div>
        <?php endif; ?>
        
        <form method="POST" action="">
            <?php echo Security::csrfField(); ?>
            
            <div class="form-group">
                <label for="username">Username or Email</label>
                <input 
                    type="text" 
                    id="username" 
                    name="username" 
                    placeholder="Enter your username or email"
                    required
                    autocomplete="username"
                    autofocus
                >
            </div>
            
            <div class="form-group">
                <label for="password">Password</label>
                <input 
                    type="password" 
                    id="password" 
                    name="password" 
                    placeholder="Enter your password"
                    required
                    autocomplete="current-password"
                >
            </div>
            
            <div class="form-options">
                <label>
                    <input type="checkbox" name="remember" value="1">
                    Remember me
                </label>
                <a href="#">Forgot password?</a>
            </div>
            
            <button type="submit" class="btn-login">Sign In</button>
        </form>
        
        <div class="login-footer">
            Don't have an account? <a href="#">Contact your administrator</a>
        </div>
        
        <div class="version-info">
            Version <?php echo Security::sanitize(APP_VERSION); ?> | &copy; <?php echo date('Y'); ?> Cloud Security Project
        </div>
    </div>
</body>
</html>

<?php
/**
 * OCP Dashboard - Main Application View
 * Only accessible after authentication
 */

if (!defined('OCP_ROOT')) {
    define('OCP_ROOT', dirname(__DIR__, 2));
}

require_once OCP_ROOT . '/config/config.php';

$auth = new Auth();
if (!$auth->isAuthenticated()) {
    header('Location: ' . BASE_URL . 'login.php');
    exit;
}

$user = $auth->getCurrentUser();
$logger = new Logger();

// Get some stats for the dashboard
try {
    $totalUsers = Database::query("SELECT COUNT(*) as count FROM users")[0]['count'] ?? 0;
    $activeUsers = Database::query("SELECT COUNT(*) as count FROM users WHERE status = 'active'")[0]['count'] ?? 0;
    $totalProjects = Database::query("SELECT COUNT(*) as count FROM projects")[0]['count'] ?? 0;
    $recentActivities = Database::query(
        "SELECT action, details, created_at FROM audit_log ORDER BY created_at DESC LIMIT 10"
    );
} catch (Exception $e) {
    $totalUsers = $activeUsers = $totalProjects = 0;
    $recentActivities = [];
}

// Get server info for sysadmin view
$serverInfo = [
    'php_version' => phpversion(),
    'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown',
    'database_host' => DB_HOST,
    'app_env' => APP_ENV,
    'app_version' => APP_VERSION
];

Security::setSecurityHeaders();
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard - <?php echo Security::sanitize(APP_NAME); ?></title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f3f4f6;
            color: #1f2937;
        }
        
        /* Layout */
        .app-container {
            display: flex;
            min-height: 100vh;
        }
        
        /* Sidebar */
        .sidebar {
            width: 260px;
            background: #1e293b;
            color: #cbd5e1;
            position: fixed;
            height: 100vh;
            overflow-y: auto;
        }
        
        .sidebar-header {
            padding: 24px 20px;
            border-bottom: 1px solid #334155;
        }
        
        .sidebar-header .logo {
            display: flex;
            align-items: center;
            gap: 12px;
        }
        
        .sidebar-header .logo-icon {
            width: 40px;
            height: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            font-size: 18px;
        }
        
        .sidebar-header h2 {
            color: white;
            font-size: 16px;
        }
        
        .sidebar-header .version {
            font-size: 11px;
            color: #64748b;
        }
        
        .nav-menu {
            padding: 16px 12px;
        }
        
        .nav-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 10px 16px;
            border-radius: 8px;
            margin-bottom: 4px;
            cursor: pointer;
            transition: background 0.2s;
            text-decoration: none;
            color: #94a3b8;
            font-size: 14px;
        }
        
        .nav-item:hover, .nav-item.active {
            background: #334155;
            color: white;
        }
        
        .nav-item svg {
            width: 18px;
            height: 18px;
        }
        
        /* Main Content */
        .main-content {
            flex: 1;
            margin-left: 260px;
            padding: 24px 32px;
        }
        
        /* Top Bar */
        .top-bar {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 28px;
            padding-bottom: 16px;
            border-bottom: 1px solid #e5e7eb;
        }
        
        .top-bar h1 {
            font-size: 24px;
            color: #111827;
        }
        
        .user-menu {
            display: flex;
            align-items: center;
            gap: 12px;
        }
        
        .user-menu .avatar {
            width: 36px;
            height: 36px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: 600;
            font-size: 14px;
        }
        
        .user-menu .user-info {
            text-align: right;
        }
        
        .user-menu .name {
            font-size: 14px;
            font-weight: 600;
            color: #111827;
        }
        
        .user-menu .role {
            font-size: 12px;
            color: #6b7280;
        }
        
        .btn-logout {
            padding: 8px 16px;
            background: #ef4444;
            color: white;
            border: none;
            border-radius: 6px;
            font-size: 13px;
            cursor: pointer;
            text-decoration: none;
        }
        
        .btn-logout:hover {
            background: #dc2626;
        }
        
        /* Stats Cards */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
            gap: 20px;
            margin-bottom: 28px;
        }
        
        .stat-card {
            background: white;
            padding: 24px;
            border-radius: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        
        .stat-card .label {
            font-size: 13px;
            color: #6b7280;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 8px;
        }
        
        .stat-card .value {
            font-size: 32px;
            font-weight: 700;
            color: #111827;
        }
        
        .stat-card .icon {
            float: right;
            width: 48px;
            height: 48px;
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 24px;
        }
        
        .stat-card.users .icon { background: #dbeafe; }
        .stat-card.active .icon { background: #dcfce7; }
        .stat-card.projects .icon { background: #fef3c7; }
        .stat-card.security .icon { background: #fee2e2; }
        
        /* Content Grid */
        .content-grid {
            display: grid;
            grid-template-columns: 2fr 1fr;
            gap: 24px;
        }
        
        .panel {
            background: white;
            border-radius: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            padding: 24px;
        }
        
        .panel h3 {
            font-size: 16px;
            margin-bottom: 16px;
            color: #111827;
        }
        
        .activity-list {
            list-style: none;
        }
        
        .activity-item {
            display: flex;
            align-items: start;
            gap: 12px;
            padding: 12px 0;
            border-bottom: 1px solid #f3f4f6;
        }
        
        .activity-item:last-child {
            border-bottom: none;
        }
        
        .activity-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            margin-top: 6px;
            flex-shrink: 0;
        }
        
        .activity-dot.login { background: #10b981; }
        .activity-dot.scan { background: #f59e0b; }
        .activity-dot.alert { background: #ef4444; }
        .activity-dot.config { background: #3b82f6; }
        
        .activity-content {
            flex: 1;
        }
        
        .activity-content .action {
            font-size: 14px;
            color: #374151;
        }
        
        .activity-content .time {
            font-size: 12px;
            color: #9ca3af;
            margin-top: 2px;
        }
        
        /* Server Info */
        .server-info table {
            width: 100%;
            font-size: 13px;
        }
        
        .server-info td {
            padding: 8px 0;
            border-bottom: 1px solid #f3f4f6;
        }
        
        .server-info td:first-child {
            color: #6b7280;
            width: 40%;
        }
        
        .server-info td:last-child {
            color: #111827;
            font-weight: 500;
        }
        
        /* Status Badge */
        .badge {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 999px;
            font-size: 11px;
            font-weight: 600;
        }
        
        .badge-success { background: #dcfce7; color: #166534; }
        .badge-warning { background: #fef3c7; color: #92400e; }
        .badge-danger { background: #fee2e2; color: #991b1b; }
        
        /* Quick Actions */
        .quick-actions {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
            margin-top: 16px;
        }
        
        .action-btn {
            padding: 12px;
            background: #f8fafc;
            border: 1px solid #e2e8f0;
            border-radius: 8px;
            text-align: center;
            cursor: pointer;
            transition: all 0.2s;
            text-decoration: none;
            color: #475569;
            font-size: 13px;
        }
        
        .action-btn:hover {
            background: #f1f5f9;
            border-color: #cbd5e1;
        }
    </style>
</head>
<body>
    <div class="app-container">
        <!-- Sidebar -->
        <aside class="sidebar">
            <div class="sidebar-header">
                <div class="logo">
                    <div class="logo-icon">OCP</div>
                    <div>
                        <h2><?php echo Security::sanitize(APP_NAME); ?></h2>
                        <div class="version">v<?php echo Security::sanitize(APP_VERSION); ?></div>
                    </div>
                </div>
            </div>
            
            <nav class="nav-menu">
                <a href="#" class="nav-item active">
                    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"/></svg>
                    Dashboard
                </a>
                <a href="#" class="nav-item">
                    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"/></svg>
                    Users
                </a>
                <a href="#" class="nav-item">
                    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/></svg>
                    Projects
                </a>
                <a href="#" class="nav-item">
                    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/></svg>
                    Security
                </a>
                <a href="#" class="nav-item">
                    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg>
                    Settings
                </a>
            </nav>
        </aside>
        
        <!-- Main Content -->
        <main class="main-content">
            <div class="top-bar">
                <h1>Dashboard</h1>
                <div class="user-menu">
                    <div class="avatar"><?php echo strtoupper(substr($user['display_name'], 0, 1)); ?></div>
                    <div class="user-info">
                        <div class="name"><?php echo Security::sanitize($user['display_name']); ?></div>
                        <div class="role">
                            <?php echo ucfirst(Security::sanitize($user['role'])); ?>
                            <span class="badge badge-success">Active</span>
                        </div>
                    </div>
                    <a href="logout.php" class="btn-logout">Logout</a>
                </div>
            </div>
            
            <!-- Stats -->
            <div class="stats-grid">
                <div class="stat-card users">
                    <div class="icon">👥</div>
                    <div class="label">Total Users</div>
                    <div class="value"><?php echo number_format($totalUsers); ?></div>
                </div>
                <div class="stat-card active">
                    <div class="icon">✅</div>
                    <div class="label">Active Users</div>
                    <div class="value"><?php echo number_format($activeUsers); ?></div>
                </div>
                <div class="stat-card projects">
                    <div class="icon">📁</div>
                    <div class="label">Projects</div>
                    <div class="value"><?php echo number_format($totalProjects); ?></div>
                </div>
                <div class="stat-card security">
                    <div class="icon">🛡️</div>
                    <div class="label">Security Alerts (24h)</div>
                    <div class="value" style="color: #ef4444;">12</div>
                </div>
            </div>
            
            <div class="content-grid">
                <!-- Recent Activity -->
                <div class="panel">
                    <h3>Recent Activity</h3>
                    <ul class="activity-list">
                        <?php if (empty($recentActivities)): ?>
                            <li class="activity-item">
                                <div class="activity-dot login"></div>
                                <div class="activity-content">
                                    <div class="action">System initialized</div>
                                    <div class="time">Just now</div>
                                </div>
                            </li>
                            <li class="activity-item">
                                <div class="activity-dot config"></div>
                                <div class="activity-content">
                                    <div class="action">Database connection established</div>
                                    <div class="time">Just now</div>
                                </div>
                            </li>
                        <?php else: ?>
                            <?php foreach ($recentActivities as $activity): ?>
                                <li class="activity-item">
                                    <div class="activity-dot <?php echo strpos($activity['action'], 'scan') !== false ? 'scan' : (strpos($activity['action'], 'alert') !== false ? 'alert' : 'login'); ?>"></div>
                                    <div class="activity-content">
                                        <div class="action"><?php echo Security::sanitize($activity['action']); ?></div>
                                        <div class="time"><?php echo Security::sanitize($activity['created_at']); ?></div>
                                    </div>
                                </li>
                            <?php endforeach; ?>
                        <?php endif; ?>
                    </ul>
                </div>
                
                <!-- Server Info & Quick Actions -->
                <div>
                    <div class="panel server-info" style="margin-bottom: 20px;">
                        <h3>Server Information</h3>
                        <table>
                            <tr><td>PHP Version</td><td><?php echo Security::sanitize($serverInfo['php_version']); ?></td></tr>
                            <tr><td>Web Server</td><td><?php echo Security::sanitize($serverInfo['server_software']); ?></td></tr>
                            <tr><td>Database Host</td><td><?php echo Security::sanitize($serverInfo['database_host']); ?></td></tr>
                            <tr><td>Environment</td><td><span class="badge badge-success"><?php echo Security::sanitize($serverInfo['app_env']); ?></span></td></tr>
                            <tr><td>App Version</td><td><?php echo Security::sanitize($serverInfo['app_version']); ?></td></tr>
                        </table>
                    </div>
                    
                    <div class="panel">
                        <h3>Quick Actions</h3>
                        <div class="quick-actions">
                            <a href="#" class="action-btn">New User</a>
                            <a href="#" class="action-btn">New Project</a>
                            <a href="#" class="action-btn">View Logs</a>
                            <a href="#" class="action-btn">Reports</a>
                        </div>
                    </div>
                </div>
            </div>
        </main>
    </div>
</body>
</html>

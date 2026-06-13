-- ============================================================================
-- OCP (Operations Control Panel) - Database Schema
-- Cloud Security Project
-- 
-- Run this on your MySQL server before deploying the application:
--   mysql -u root -p < schema.sql
-- Or use Azure Database for MySQL and run via Azure Cloud Shell
-- ============================================================================

-- Create database
CREATE DATABASE IF NOT EXISTS ocp_db 
    CHARACTER SET utf8mb4 
    COLLATE utf8mb4_unicode_ci;

USE ocp_db;

-- ============================================================================
-- USERS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(100),
    role ENUM('user', 'admin', 'superadmin') DEFAULT 'user',
    status ENUM('active', 'inactive', 'suspended') DEFAULT 'active',
    failed_attempts INT DEFAULT 0,
    locked_until DATETIME NULL,
    last_login DATETIME NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_email (email),
    INDEX idx_status (status),
    INDEX idx_role (role)
) ENGINE=InnoDB;

-- ============================================================================
-- PROJECTS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS projects (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    status ENUM('active', 'archived', 'draft') DEFAULT 'draft',
    owner_id INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_owner (owner_id),
    INDEX idx_status (status)
) ENGINE=InnoDB;

-- ============================================================================
-- AUDIT LOG TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS audit_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NULL,
    action VARCHAR(100) NOT NULL,
    details JSON,
    ip_address VARCHAR(45),
    user_agent VARCHAR(255),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user (user_id),
    INDEX idx_action (action),
    INDEX idx_created (created_at)
) ENGINE=InnoDB;

-- ============================================================================
-- SECURITY ALERTS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS security_alerts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    severity ENUM('info', 'low', 'medium', 'high', 'critical') NOT NULL,
    category VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    source_ip VARCHAR(45),
    target VARCHAR(100),
    rule_id VARCHAR(50),
    status ENUM('new', 'acknowledged', 'resolved', 'false_positive') DEFAULT 'new',
    assigned_to INT NULL,
    resolved_at DATETIME NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_severity (severity),
    INDEX idx_status (status),
    INDEX idx_created (created_at),
    INDEX idx_category (category)
) ENGINE=InnoDB;

-- ============================================================================
-- API TOKENS TABLE (for API authentication)
-- ============================================================================
CREATE TABLE IF NOT EXISTS api_tokens (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    token_hash VARCHAR(255) NOT NULL,
    name VARCHAR(100),
    scopes JSON,
    expires_at DATETIME NOT NULL,
    last_used_at DATETIME NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_token (token_hash(64)),
    INDEX idx_user (user_id),
    INDEX idx_expires (expires_at)
) ENGINE=InnoDB;

-- ============================================================================
-- SYSTEM CONFIGURATION TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS system_config (
    config_key VARCHAR(100) PRIMARY KEY,
    config_value TEXT,
    config_group VARCHAR(50) DEFAULT 'general',
    is_sensitive BOOLEAN DEFAULT FALSE,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_group (config_group)
) ENGINE=InnoDB;

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Insert default admin user (password: Admin@OCP2024!)
-- CHANGE THIS PASSWORD AFTER FIRST LOGIN!
INSERT IGNORE INTO users (id, username, email, password_hash, display_name, role, status) VALUES
(1, 'admin', 'admin@ocp.local', '$argon2id$v=19$m=65536,t=4,p=3$c29tZXNhbHR0aW5n$KqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQ', 'System Administrator', 'superadmin', 'active');

-- Insert sample users
INSERT IGNORE INTO users (id, username, email, password_hash, display_name, role, status) VALUES
(2, 'jdoe', 'john.doe@company.com', '$argon2id$v=19$m=65536,t=4,p=3$c29tZXNhbHR0aW5n$KqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQ', 'John Doe', 'admin', 'active'),
(3, 'asmith', 'alice.smith@company.com', '$argon2id$v=19$m=65536,t=4,p=3$c29tZXNhbHR0aW5n$KqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQ', 'Alice Smith', 'user', 'active'),
(4, 'bwilson', 'bob.wilson@company.com', '$argon2id$v=19$m=65536,t=4,p=3$c29tZXNhbHR0aW5n$KqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQ', 'Bob Wilson', 'user', 'active'),
(5, 'ctester', 'charlie.tester@company.com', '$argon2id$v=19$m=65536,t=4,p=3$c29tZXNhbHR0aW5n$KqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQqKqQ', 'Charlie Tester', 'user', 'inactive');

-- Insert sample projects
INSERT IGNORE INTO projects (id, name, description, status, owner_id) VALUES
(1, 'Cloud Migration Phase 1', 'Migrate on-premise infrastructure to Azure', 'active', 2),
(2, 'Security Audit 2024', 'Annual security assessment and penetration testing', 'active', 1),
(3, 'SIEM Deployment', 'Wazuh + Suricata integration project', 'active', 3),
(4, 'Vault PAM Implementation', 'HashiCorp Vault privileged access management', 'draft', 2),
(5, 'Compliance Review', 'GDPR and ISO 27001 compliance verification', 'archived', 4);

-- Insert sample system configuration
INSERT IGNORE INTO system_config (config_key, config_value, config_group, is_sensitive) VALUES
('app.name', 'Operations Control Panel', 'general', FALSE),
('app.maintenance_mode', 'false', 'general', FALSE),
('security.max_login_attempts', '5', 'security', FALSE),
('security.session_timeout', '3600', 'security', FALSE),
('security.password_policy', 'strong', 'security', FALSE),
('email.smtp_host', 'smtp.company.com', 'email', FALSE),
('email.smtp_port', '587', 'email', FALSE),
('email.smtp_user', 'ocp@company.com', 'email', TRUE),
('email.smtp_password', 'SuperSecretSMTP123!', 'email', TRUE);

-- Insert sample security alerts
INSERT IGNORE INTO security_alerts (id, severity, category, title, description, source_ip, target, rule_id, status) VALUES
(1, 'high', 'brute_force', 'SSH Brute Force Detected', 'Multiple failed SSH login attempts from single IP', '192.168.1.200', 'suricata-ubuntu', '5712', 'new'),
(2, 'medium', 'reconnaissance', 'Port Scan Detected', 'Nmap scan detected against Ubuntu target', '192.168.1.200', 'suricata-ubuntu', '100011', 'acknowledged'),
(3, 'critical', 'exploit', 'Log4Shell Attempt', 'Log4j JNDI injection payload detected', '192.168.1.200', 'ocp-webapp', '100040', 'new'),
(4, 'low', 'information', 'New Device Connected', 'Windows 10 agent registered with Wazuh', '192.168.1.103', 'wazuh-server', '601', 'resolved'),
(5, 'medium', 'web_attack', 'Directory Traversal Attempt', 'Path traversal payload in HTTP request', '192.168.1.200', 'ocp-webapp', '100045', 'new');

-- ============================================================================
-- CREATE READ-ONLY USER FOR APPLICATION (Security Best Practice)
-- Replace 'app_password' with a strong password, ideally from Vault
-- ============================================================================
-- CREATE USER IF NOT EXISTS 'ocp_app'@'%' IDENTIFIED BY 'change_me_strong_password';
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ocp_db.* TO 'ocp_app'@'%';
-- FLUSH PRIVILEGES;

-- For Azure Database for MySQL, use:
-- CREATE USER IF NOT EXISTS 'ocp_app'@'%' IDENTIFIED BY 'change_me_strong_password';
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ocp_db.* TO 'ocp_app'@'%';
-- FLUSH PRIVILEGES;

SELECT 'OCP Database initialized successfully!' AS status;
SELECT CONCAT('Total users: ', COUNT(*)) FROM users;
SELECT CONCAT('Total projects: ', COUNT(*)) FROM projects;
SELECT CONCAT('Total security alerts: ', COUNT(*)) FROM security_alerts;

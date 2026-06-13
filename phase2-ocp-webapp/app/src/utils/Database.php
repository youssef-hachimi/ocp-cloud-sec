<?php
/**
 * OCP Database Manager
 * Handles MySQL connections with support for HashiCorp Vault dynamic credentials
 */

class Database
{
    private static ?PDO $instance = null;
    private static array $credentials = [];
    
    /**
     * Get database connection (singleton pattern)
     */
    public static function getConnection(): PDO
    {
        if (self::$instance === null) {
            self::$instance = self::createConnection();
        }
        return self::$instance;
    }
    
    /**
     * Create new PDO connection
     */
    private static function createConnection(): PDO
    {
        $creds = self::getCredentials();
        
        $dsn = sprintf(
            'mysql:host=%s;port=%s;dbname=%s;charset=%s',
            $creds['host'],
            $creds['port'],
            $creds['dbname'],
            $creds['charset']
        );
        
        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES {$creds['charset']} COLLATE {$creds['charset']}_unicode_ci"
        ];
        
        try {
            $pdo = new PDO($dsn, $creds['user'], $creds['pass'], $options);
            
            // Log successful connection in development
            if (APP_ENV === 'development') {
                error_log("Database connected to {$creds['host']}:{$creds['port']}");
            }
            
            return $pdo;
        } catch (PDOException $e) {
            error_log("Database connection failed: " . $e->getMessage());
            throw new Exception("Database connection failed. Please try again later.");
        }
    }
    
    /**
     * Get database credentials - supports Vault integration
     */
    private static function getCredentials(): array
    {
        // Check if we already have valid credentials (Vault TTL management)
        if (!empty(self::$credentials)) {
            // Check if credentials are still valid (simple TTL check)
            if (isset(self::$credentials['expires_at']) && time() < self::$credentials['expires_at']) {
                return self::$credentials;
            }
        }
        
        // If Vault is enabled, fetch dynamic credentials
        if (VAULT_ENABLED) {
            try {
                self::$credentials = self::fetchVaultCredentials();
                return self::$credentials;
            } catch (Exception $e) {
                error_log("Vault credential fetch failed, falling back to static: " . $e->getMessage());
                // Fall through to static credentials
            }
        }
        
        // Use static configuration
        self::$credentials = [
            'host' => DB_HOST,
            'port' => DB_PORT,
            'dbname' => DB_NAME,
            'user' => DB_USER,
            'pass' => DB_PASS,
            'charset' => DB_CHARSET,
            'expires_at' => time() + 3600 // Static creds don't expire, but we check anyway
        ];
        
        return self::$credentials;
    }
    
    /**
     * Fetch dynamic database credentials from HashiCorp Vault
     * Phase 4: PAM Integration
     */
    private static function fetchVaultCredentials(): array
    {
        if (!VAULT_ENABLED) {
            throw new Exception("Vault is not enabled");
        }
        
        // Step 1: Authenticate with AppRole
        $authPayload = json_encode([
            'role_id' => VAULT_ROLE_ID,
            'secret_id' => VAULT_SECRET_ID
        ]);
        
        $ch = curl_init(VAULT_ADDR . '/v1/auth/approle/login');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $authPayload);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($httpCode !== 200) {
            throw new Exception("Vault authentication failed: HTTP $httpCode");
        }
        
        $authData = json_decode($response, true);
        $vaultToken = $authData['auth']['client_token'] ?? null;
        
        if (!$vaultToken) {
            throw new Exception("No Vault token received");
        }
        
        // Step 2: Read database credentials from Vault
        $ch = curl_init(VAULT_ADDR . '/v1/' . VAULT_DB_PATH);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ["X-Vault-Token: $vaultToken"]);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($httpCode !== 200) {
            throw new Exception("Failed to read Vault secret: HTTP $httpCode");
        }
        
        $secretData = json_decode($response, true);
        $data = $secretData['data']['data'] ?? [];
        
        $leaseDuration = $secretData['lease_duration'] ?? 3600;
        
        self::$credentials = [
            'host' => $data['db_host'] ?? DB_HOST,
            'port' => $data['db_port'] ?? DB_PORT,
            'dbname' => $data['db_name'] ?? DB_NAME,
            'user' => $data['username'] ?? DB_USER,
            'pass' => $data['password'] ?? DB_PASS,
            'charset' => DB_CHARSET,
            'expires_at' => time() + $leaseDuration - 60, // Renew 1 min before expiry
            'vault_token' => $vaultToken,
            'lease_id' => $secretData['lease_id'] ?? null
        ];
        
        error_log("Vault dynamic credentials obtained, expires in {$leaseDuration}s");
        
        return self::$credentials;
    }
    
    /**
     * Execute a prepared query and return results
     */
    public static function query(string $sql, array $params = []): array
    {
        $stmt = self::getConnection()->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }
    
    /**
     * Execute a prepared statement (INSERT, UPDATE, DELETE)
     */
    public static function execute(string $sql, array $params = []): int
    {
        $stmt = self::getConnection()->prepare($sql);
        $stmt->execute($params);
        return $stmt->rowCount();
    }
    
    /**
     * Get last inserted ID
     */
    public static function lastInsertId(): string
    {
        return self::getConnection()->lastInsertId();
    }
    
    /**
     * Begin a transaction
     */
    public static function beginTransaction(): void
    {
        self::getConnection()->beginTransaction();
    }
    
    /**
     * Commit a transaction
     */
    public static function commit(): void
    {
        self::getConnection()->commit();
    }
    
    /**
     * Rollback a transaction
     */
    public static function rollback(): void
    {
        self::getConnection()->rollBack();
    }
    
    /**
     * Close the database connection
     */
    public static function close(): void
    {
        self::$instance = null;
        self::$credentials = [];
    }
}

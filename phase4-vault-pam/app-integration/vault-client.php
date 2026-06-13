<?php
/**
 * HashiCorp Vault Client for OCP Application
 * Cloud Security Project - Phase 4 PAM Integration
 * 
 * This class handles:
 *   - AppRole authentication
 *   - Secret retrieval (KV v2)
 *   - Dynamic database credentials
 *   - Token lifecycle management
 * 
 * Usage:
 *   $vault = new VaultClient();
 *   $dbCreds = $vault->getDatabaseCredentials();
 */

class VaultClient
{
    private string $vaultAddr;
    private string $roleId;
    private string $secretId;
    private ?string $token = null;
    private int $tokenExpiry = 0;
    private Logger $logger;
    
    public function __construct()
    {
        $this->vaultAddr = rtrim(VAULT_ADDR, '/');
        $this->roleId = VAULT_ROLE_ID;
        $this->secretId = VAULT_SECRET_ID;
        $this->logger = new Logger();
        
        if (VAULT_ENABLED) {
            $this->authenticate();
        }
    }
    
    /**
     * Authenticate with Vault using AppRole
     */
    private function authenticate(): void
    {
        try {
            $ch = curl_init("{$this->vaultAddr}/v1/auth/approle/login");
            
            $payload = json_encode([
                'role_id' => $this->roleId,
                'secret_id' => $this->secretId
            ]);
            
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_POST => true,
                CURLOPT_POSTFIELDS => $payload,
                CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
                CURLOPT_SSL_VERIFYPEER => false, // Set to true with proper CA cert
                CURLOPT_TIMEOUT => 10
            ]);
            
            $response = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            
            if ($httpCode !== 200) {
                throw new Exception("Vault authentication failed: HTTP $httpCode");
            }
            
            $data = json_decode($response, true);
            $this->token = $data['auth']['client_token'] ?? null;
            $leaseDuration = $data['auth']['lease_duration'] ?? 3600;
            $this->tokenExpiry = time() + $leaseDuration - 300; // Renew 5 min early
            
            if (!$this->token) {
                throw new Exception("No token received from Vault");
            }
            
            $this->logger->info('Vault authentication successful', [
                'lease_duration' => $leaseDuration
            ]);
            
        } catch (Exception $e) {
            $this->logger->error('Vault authentication failed', ['error' => $e->getMessage()]);
            throw $e;
        }
    }
    
    /**
     * Ensure token is valid (re-auth if needed)
     */
    private function ensureAuthenticated(): void
    {
        if (time() >= $this->tokenExpiry) {
            $this->logger->info('Vault token expired, re-authenticating');
            $this->authenticate();
        }
    }
    
    /**
     * Make authenticated API request to Vault
     */
    private function apiRequest(string $method, string $path, ?array $body = null): array
    {
        $this->ensureAuthenticated();
        
        $url = "{$this->vaultAddr}/v1/{$path}";
        $ch = curl_init($url);
        
        $headers = [
            "X-Vault-Token: {$this->token}",
            'Content-Type: application/json'
        ];
        
        $options = [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_TIMEOUT => 10
        ];
        
        if ($method === 'POST' && $body !== null) {
            $options[CURLOPT_POST] = true;
            $options[CURLOPT_POSTFIELDS] = json_encode($body);
        } elseif ($method === 'LIST') {
            $options[CURLOPT_CUSTOMREQUEST] = 'LIST';
        }
        
        curl_setopt_array($ch, $options);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($httpCode >= 400) {
            throw new Exception("Vault API error: HTTP $httpCode - $response");
        }
        
        return json_decode($response, true) ?? [];
    }
    
    /**
     * Read secret from KV v2 engine
     */
    public function readSecret(string $path): array
    {
        try {
            $data = $this->apiRequest('GET', "secret/data/{$path}");
            
            $this->logger->info('Vault secret read', ['path' => $path]);
            
            return $data['data']['data'] ?? [];
            
        } catch (Exception $e) {
            $this->logger->error('Failed to read Vault secret', [
                'path' => $path,
                'error' => $e->getMessage()
            ]);
            throw $e;
        }
    }
    
    /**
     * Write secret to KV v2 engine
     */
    public function writeSecret(string $path, array $data): void
    {
        try {
            $this->apiRequest('POST', "secret/data/{$path}", ['data' => $data]);
            
            $this->logger->audit('vault_secret_write', ['path' => $path]);
            
        } catch (Exception $e) {
            $this->logger->error('Failed to write Vault secret', [
                'path' => $path,
                'error' => $e->getMessage()
            ]);
            throw $e;
        }
    }
    
    /**
     * Get database credentials (static or dynamic)
     */
    public function getDatabaseCredentials(): array
    {
        // Try dynamic credentials first
        try {
            $creds = $this->apiRequest('GET', 'database/creds/ocp-app');
            
            $this->logger->info('Dynamic database credentials obtained');
            
            return [
                'host' => DB_HOST,
                'port' => DB_PORT,
                'dbname' => DB_NAME,
                'user' => $creds['data']['username'],
                'pass' => $creds['data']['password'],
                'charset' => DB_CHARSET,
                'lease_id' => $creds['lease_id'],
                'lease_duration' => $creds['lease_duration'],
                'renewable' => $creds['renewable'],
                'dynamic' => true
            ];
            
        } catch (Exception $e) {
            $this->logger->warning('Dynamic credentials failed, falling back to static secret', [
                'error' => $e->getMessage()
            ]);
            
            // Fall back to static credentials stored in KV
            $secret = $this->readSecret('ocp/database');
            
            return [
                'host' => $secret['host'] ?? DB_HOST,
                'port' => $secret['port'] ?? DB_PORT,
                'dbname' => $secret['db_name'] ?? DB_NAME,
                'user' => $secret['username'] ?? DB_USER,
                'pass' => $secret['password'] ?? DB_PASS,
                'charset' => DB_CHARSET,
                'dynamic' => false
            ];
        }
    }
    
    /**
     * Renew lease (for dynamic credentials)
     */
    public function renewLease(string $leaseId): array
    {
        try {
            return $this->apiRequest('POST', 'sys/leases/renew', [
                'lease_id' => $leaseId,
                'increment' => 3600
            ]);
        } catch (Exception $e) {
            $this->logger->error('Failed to renew lease', [
                'lease_id' => $leaseId,
                'error' => $e->getMessage()
            ]);
            throw $e;
        }
    }
    
    /**
     * Check Vault health status
     */
    public function healthCheck(): array
    {
        $ch = curl_init("{$this->vaultAddr}/v1/sys/health");
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_TIMEOUT => 5
        ]);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        $status = match($httpCode) {
            200 => ['status' => 'active', 'sealed' => false, 'standby' => false],
            429 => ['status' => 'unsealed_standby', 'sealed' => false, 'standby' => true],
            472 => ['status' => 'recovery_replication', 'sealed' => false, 'standby' => false],
            473 => ['status' => 'performance_standby', 'sealed' => false, 'standby' => true],
            501 => ['status' => 'not_initialized', 'sealed' => true],
            503 => ['status' => 'sealed', 'sealed' => true],
            default => ['status' => 'unknown', 'http_code' => $httpCode]
        };
        
        return $status;
    }
    
    /**
     * Check if Vault integration is enabled
     */
    public static function isEnabled(): bool
    {
        return VAULT_ENABLED;
    }
}

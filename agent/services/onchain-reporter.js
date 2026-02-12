const { ethers } = require('ethers');

// ABI fragments for ChainGuard and SecurityRegistry
const CHAINGUARD_ABI = [
    'function registerContract(address contractAddress, uint256 scanInterval) external',
    'function scanContract(address contractAddress) external returns (uint256 reportId, uint256 certificateId)',
    'function setAIAgent(address _aiAgent) external',
    'function getMonitoringStatus(address contractAddress) external view returns (bool isActive, uint256 lastScan, uint256 scanCount, uint256 nextScan)',
    'function getSystemStats() external view returns (uint256 totalContracts, uint256 totalScans, uint256 activeContracts)',
    'function getVulnerabilitySummary(address contractAddress) external view returns (uint8 critical, uint8 high, uint8 medium, uint8 low)',
    'function getContractCertificates(address contractAddress) external view returns (uint256[])',
    'event ContractRegistered(address indexed contractAddress, uint256 scanInterval)',
    'event ScanCompleted(address indexed contractAddress, uint256 indexed reportId, uint256 indexed certificateId)',
];

const SECURITY_REGISTRY_ABI = [
    'function registerContract(address _contractAddress) external',
    'function reportVulnerability(address _contractAddress, string _ipfsHash, uint8 _critical, uint8 _high, uint8 _medium, uint8 _low) external returns (uint256)',
    'function pauseContract(address _contractAddress) external',
    'function unpauseContract(address _contractAddress) external',
    'function markResolved(uint256 _reportId) external',
    'function isMonitored(address _contractAddress) external view returns (bool)',
    'function isPaused(address _contractAddress) external view returns (bool)',
    'function reportCounter() external view returns (uint256)',
    'function vulnerabilityReports(uint256) external view returns (uint256 id, string ipfsHash, address contractAddress, uint8 critical, uint8 high, uint8 medium, uint8 low, uint256 timestamp, bool resolved)',
    'event VulnerabilityReported(uint256 indexed reportId, address indexed contractAddress, uint8 severity)',
    'event ContractPaused(address indexed contractAddress)',
];

const AUDIT_NFT_ABI = [
    'function getCertificate(uint256 tokenId) external view returns (uint256 reportId, address contractAddress, uint8 maxSeverity, uint256 auditTimestamp, string auditor, bool isValid)',
    'function getContractCertificates(address contractAddress) external view returns (uint256[])',
    'function getValidCertificatesCount() external view returns (uint256)',
    'function tokenURI(uint256 tokenId) external view returns (string)',
    'event CertificateMinted(uint256 indexed tokenId, address indexed to, address indexed contractAddress, uint256 reportId)',
];

class OnchainReporter {
    constructor(wallet) {
        this.wallet = wallet;
        this.chainGuard = null;
        this.securityRegistry = null;
        this.auditNFT = null;
    }

    /**
     * Connect to deployed contracts
     * @param {string} chainGuardAddress - ChainGuard contract address
     * @param {string} registryAddress - SecurityRegistry address (optional, read from ChainGuard)
     * @param {string} nftAddress - AuditNFT address (optional, read from ChainGuard)
     */
    async connect(chainGuardAddress, registryAddress, nftAddress) {
        this.chainGuard = new ethers.Contract(chainGuardAddress, CHAINGUARD_ABI, this.wallet);

        if (registryAddress) {
            this.securityRegistry = new ethers.Contract(registryAddress, SECURITY_REGISTRY_ABI, this.wallet);
        }
        if (nftAddress) {
            this.auditNFT = new ethers.Contract(nftAddress, AUDIT_NFT_ABI, this.wallet);
        }

        console.log(`⛓️ Connected to ChainGuard at ${chainGuardAddress}`);
    }

    /**
     * Register a contract for monitoring via ChainGuard
     * @param {string} contractAddress - Contract to register
     * @param {number} scanInterval - Scan interval in seconds (default 1 hour)
     * @returns {Object} Transaction receipt
     */
    async registerContract(contractAddress, scanInterval = 3600) {
        try {
            const tx = await this.chainGuard.registerContract(contractAddress, scanInterval);
            const receipt = await tx.wait();
            console.log(`📝 Contract ${contractAddress} registered. Tx: ${receipt.hash}`);
            return { hash: receipt.hash, blockNumber: receipt.blockNumber };
        } catch (error) {
            console.error('Register error:', error.reason || error.message);
            throw error;
        }
    }

    /**
     * Submit vulnerability report on-chain
     * @param {string} contractAddress - Vulnerable contract
     * @param {string} ipfsHash - IPFS hash of full report
     * @param {Object} counts - { critical, high, medium, low }
     * @returns {Object} { reportId, txHash }
     */
    async submitReport(contractAddress, ipfsHash, counts) {
        try {
            if (!this.securityRegistry) {
                throw new Error('SecurityRegistry not connected');
            }

            const tx = await this.securityRegistry.reportVulnerability(
                contractAddress,
                ipfsHash,
                counts.critical || 0,
                counts.high || 0,
                counts.medium || 0,
                counts.low || 0
            );

            const receipt = await tx.wait();

            // Extract reportId from events
            let reportId = 0;
            for (const log of receipt.logs) {
                try {
                    const parsed = this.securityRegistry.interface.parseLog(log);
                    if (parsed?.name === 'VulnerabilityReported') {
                        reportId = Number(parsed.args.reportId);
                    }
                } catch { /* skip unparseable logs */ }
            }

            console.log(`🚨 Report submitted. ID: ${reportId}, Tx: ${receipt.hash}`);
            return { reportId, txHash: receipt.hash };
        } catch (error) {
            console.error('Submit report error:', error.reason || error.message);
            throw error;
        }
    }

    /**
     * Trigger a scan via ChainGuard (combines scan + report + NFT mint)
     * @param {string} contractAddress - Contract to scan
     * @returns {Object} { reportId, certificateId, txHash }
     */
    async triggerScan(contractAddress) {
        try {
            const tx = await this.chainGuard.scanContract(contractAddress);
            const receipt = await tx.wait();

            let reportId = 0, certificateId = 0;
            for (const log of receipt.logs) {
                try {
                    const parsed = this.chainGuard.interface.parseLog(log);
                    if (parsed?.name === 'ScanCompleted') {
                        reportId = Number(parsed.args.reportId);
                        certificateId = Number(parsed.args.certificateId);
                    }
                } catch { /* skip */ }
            }

            console.log(`🔍 Scan complete. Report: ${reportId}, Certificate: ${certificateId}`);
            return { reportId, certificateId, txHash: receipt.hash };
        } catch (error) {
            console.error('Scan error:', error.reason || error.message);
            throw error;
        }
    }

    /**
     * Get system stats from ChainGuard
     * @returns {Object} { totalContracts, totalScans, activeContracts }
     */
    async getStats() {
        try {
            const [totalContracts, totalScans, activeContracts] = await this.chainGuard.getSystemStats();
            return {
                totalContracts: Number(totalContracts),
                totalScans: Number(totalScans),
                activeContracts: Number(activeContracts)
            };
        } catch (error) {
            console.error('Stats error:', error.message);
            return { totalContracts: 0, totalScans: 0, activeContracts: 0 };
        }
    }

    /**
     * Get vulnerability summary for a contract
     * @param {string} contractAddress - Contract address
     * @returns {Object} { critical, high, medium, low }
     */
    async getVulnSummary(contractAddress) {
        try {
            const [critical, high, medium, low] = await this.chainGuard.getVulnerabilitySummary(contractAddress);
            return { critical, high, medium, low };
        } catch (error) {
            console.error('Vuln summary error:', error.message);
            return { critical: 0, high: 0, medium: 0, low: 0 };
        }
    }
}

module.exports = OnchainReporter;

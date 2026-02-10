// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./SecurityRegistry.sol";
import "./AuditNFT.sol";
import "./VulnerabilityScanner.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ChainGuard
/// @notice Main ChainGuard AI contract orchestrating security monitoring and audit certificates
/// @dev Integrates vulnerability scanning, registry management, and NFT certificates
/// @author ChainGuard AI Team
contract ChainGuard is Ownable, ReentrancyGuard {
    using VulnerabilityScanner for bytes;
    
    /// @dev Struct to store monitoring configuration
    struct MonitoringConfig {
        bool isActive;              // Whether monitoring is active
        uint256 scanInterval;       // Time between scans in seconds
        uint256 lastScanTimestamp;  // Last scan timestamp
        uint256 scanCount;          // Total number of scans performed
    }
    
    // Events
    /// @notice Emitted when a new contract is registered for monitoring
    /// @param contractAddress Address of the registered contract
    /// @param owner Address that registered the contract
    event ContractRegistered(address indexed contractAddress, address indexed owner);
    
    /// @notice Emitted when a security scan is completed
    /// @param contractAddress Address of the scanned contract
    /// @param reportId ID of the generated vulnerability report
    /// @param certificateId ID of the minted audit certificate
    /// @param criticalCount Number of critical vulnerabilities found
    event SecurityScanCompleted(
        address indexed contractAddress,
        uint256 indexed reportId,
        uint256 indexed certificateId,
        uint8 criticalCount
    );
    
    /// @notice Emitted when monitoring configuration is updated
    /// @param contractAddress Address of the contract
    /// @param isActive New monitoring status
    /// @param scanInterval New scan interval
    event MonitoringConfigUpdated(
        address indexed contractAddress,
        bool isActive,
        uint256 scanInterval
    );
    
    // State variables
    SecurityRegistry public securityRegistry;
    AuditNFT public auditNFT;
    
    mapping(address => MonitoringConfig) public monitoringConfigs;
    mapping(address => bytes) public contractBytecode;
    mapping(address => uint256) public contractReportIds;
    
    uint256 public totalContractsMonitored;
    uint256 public totalScansPerformed;
    
    address public aiAgent;
    string public baseTokenURI;
    
    /// @dev Custom errors for gas efficiency
    error InvalidAddress();
    error NotRegistered();
    error ScanInProgress();
    error InvalidInterval();
    error NotAuthorized();
    
    /// @notice Initializes the ChainGuard contract
    /// @param initialOwner Address that will own the contract
    /// @param _baseTokenURI Base URI for NFT metadata
    constructor(address initialOwner, string memory _baseTokenURI) Ownable(initialOwner) {
        aiAgent = msg.sender;
        baseTokenURI = _baseTokenURI;
        
        // Deploy dependent contracts
        securityRegistry = new SecurityRegistry(initialOwner);
        auditNFT = new AuditNFT(initialOwner, address(securityRegistry), _baseTokenURI);
    }
    
    /// @notice Register a contract for comprehensive monitoring
    /// @param contractAddress Address of the contract to monitor
    /// @param scanInterval Time between automatic scans (in seconds)
    /// @dev Stores contract bytecode for analysis
    function registerContract(address contractAddress, uint256 scanInterval) external nonReentrant {
        if (contractAddress == address(0)) revert InvalidAddress();
        if (scanInterval < 60) revert InvalidInterval(); // Minimum 1 minute
        if (monitoringConfigs[contractAddress].isActive) revert NotRegistered();
        
        // Store contract bytecode
        contractBytecode[contractAddress] = address(contractAddress).code;
        
        // Set up monitoring configuration
        monitoringConfigs[contractAddress] = MonitoringConfig({
            isActive: true,
            scanInterval: scanInterval,
            lastScanTimestamp: 0,
            scanCount: 0
        });
        
        // Register in security registry
        securityRegistry.registerContract(contractAddress);
        
        totalContractsMonitored++;
        
        emit ContractRegistered(contractAddress, msg.sender);
        emit MonitoringConfigUpdated(contractAddress, true, scanInterval);
    }
    
    /// @notice Perform immediate security scan on a contract
    /// @param contractAddress Address of the contract to scan
    /// @return reportId ID of the generated vulnerability report
    /// @return certificateId ID of the minted audit certificate
    function scanContract(address contractAddress) 
        external 
        nonReentrant 
        returns (uint256 reportId, uint256 certificateId) 
    {
        if (!monitoringConfigs[contractAddress].isActive) revert NotRegistered();
        
        // Get contract bytecode
        bytes memory bytecode = contractBytecode[contractAddress];
        if (bytecode.length == 0) revert NotRegistered();
        
        // Perform comprehensive vulnerability scan
        VulnerabilityScanner.AnalysisResult memory analysis = 
            VulnerabilityScanner.comprehensiveScan(bytecode);
        
        // Generate IPFS hash (simplified - in production, upload to IPFS)
        string memory ipfsHash = generateIPFSHash(analysis);
        
        // Submit vulnerability report to registry
        reportId = securityRegistry.reportVulnerability(
            contractAddress,
            ipfsHash,
            uint8(analysis.criticalCount),
            uint8(analysis.highCount),
            uint8(analysis.mediumCount),
            uint8(analysis.lowCount)
        );
        
        // Mint audit certificate NFT
        certificateId = auditNFT.mintCertificate(
            msg.sender,
            contractAddress,
            reportId,
            uint8(analysis.criticalCount > 0 ? 4 : 
                  analysis.highCount > 0 ? 3 : 
                  analysis.mediumCount > 0 ? 2 : 1),
            "ChainGuard AI Scanner",
            ipfsHash
        );
        
        // Update monitoring configuration
        MonitoringConfig storage config = monitoringConfigs[contractAddress];
        config.lastScanTimestamp = block.timestamp;
        config.scanCount++;
        
        totalScansPerformed++;
        
        emit SecurityScanCompleted(
            contractAddress,
            reportId,
            certificateId,
            uint8(analysis.criticalCount)
        );
    }
    
    /// @notice Update monitoring configuration for a contract
    /// @param contractAddress Address of the contract
    /// @param isActive Whether monitoring should be active
    /// @param scanInterval New scan interval
    function updateMonitoringConfig(
        address contractAddress,
        bool isActive,
        uint256 scanInterval
    ) external {
        // Get the monitored contract info to check owner
        (, address contractOwner,,,) = securityRegistry.monitoredContracts(contractAddress);
        if (msg.sender != contractOwner && msg.sender != owner()) revert NotAuthorized();
        
        if (scanInterval < 60) revert InvalidInterval();
        
        monitoringConfigs[contractAddress].isActive = isActive;
        monitoringConfigs[contractAddress].scanInterval = scanInterval;
        
        emit MonitoringConfigUpdated(contractAddress, isActive, scanInterval);
    }
    
    /// @notice Get monitoring status for a contract
    /// @param contractAddress Address of the contract
    /// @return isActive Whether monitoring is active
    /// @return lastScanTimestamp Last scan timestamp
    /// @return scanCount Total number of scans performed
    /// @return nextScanTimestamp When the next scan is scheduled
    function getMonitoringStatus(address contractAddress) 
        external 
        view 
        returns (
            bool isActive,
            uint256 lastScanTimestamp,
            uint256 scanCount,
            uint256 nextScanTimestamp
        ) 
    {
        MonitoringConfig memory config = monitoringConfigs[contractAddress];
        return (
            config.isActive,
            config.lastScanTimestamp,
            config.scanCount,
            config.lastScanTimestamp + config.scanInterval
        );
    }
    
    /// @notice Get contract vulnerability summary
    /// @param contractAddress Address of the contract
    /// @return critical Number of critical vulnerabilities
    /// @return high Number of high severity vulnerabilities
    /// @return medium Number of medium severity vulnerabilities
    /// @return low Number of low severity vulnerabilities
    function getVulnerabilitySummary(address contractAddress) 
        external 
        view 
        returns (uint8 critical, uint8 high, uint8 medium, uint8 low) 
    {
        return securityRegistry.getVulnerabilitySummary(contractAddress);
    }
    
    /// @notice Get all certificates for a contract
    /// @param contractAddress Address of the contract
    /// @return certificateIds Array of certificate token IDs
    function getContractCertificates(address contractAddress) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return auditNFT.getContractCertificates(contractAddress);
    }
    
    /// @notice Set AI agent address
    /// @param _aiAgent New AI agent address
    /// @dev Only callable by contract owner
    function setAIAgent(address _aiAgent) external onlyOwner {
        if (_aiAgent == address(0)) revert InvalidAddress();
        aiAgent = _aiAgent;
    }
    
    /// @notice Set base token URI for NFTs
    /// @param _baseTokenURI New base URI
    /// @dev Only callable by contract owner
    function setBaseTokenURI(string memory _baseTokenURI) external onlyOwner {
        baseTokenURI = _baseTokenURI;
        auditNFT.setBaseTokenURI(_baseTokenURI);
    }
    
    /// @notice Get system statistics
    /// @return totalContracts Total number of monitored contracts
    /// @return totalScans Total number of scans performed
    /// @return activeContracts Number of actively monitored contracts
    function getSystemStats() 
        external 
        view 
        returns (uint256 totalContracts, uint256 totalScans, uint256 activeContracts) 
    {
        totalContracts = totalContractsMonitored;
        totalScans = totalScansPerformed;
        
        // Count active contracts (simplified implementation)
        activeContracts = totalContracts; // In production, maintain separate counter
    }
    
    /// @notice Generate IPFS hash for analysis results
    /// @param analysis Vulnerability analysis results
    /// @return ipfsHash Generated IPFS hash
    /// @dev Simplified implementation - in production, upload to IPFS
    function generateIPFSHash(VulnerabilityScanner.AnalysisResult memory analysis) 
        internal 
        pure 
        returns (string memory) 
    {
        // Generate deterministic hash from analysis data
        bytes memory data = abi.encode(
            analysis.contractHash,
            analysis.totalVulnerabilities,
            analysis.criticalCount,
            analysis.highCount,
            analysis.mediumCount,
            analysis.lowCount,
            analysis.scanTimestamp
        );
        
        bytes32 hash = keccak256(data);
        return string(abi.encodePacked("Qm", _toBase58(uint256(hash))));
    }
    
    /// @dev Convert uint256 to base58 string (simplified)
    function _toBase58(uint256 value) internal pure returns (bytes memory) {
        if (value == 0) return "1";
        
        bytes memory alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
        bytes memory result = new bytes(50);
        uint256 index = 0;
        
        while (value > 0) {
            uint256 remainder = value % 58;
            result[index] = alphabet[remainder];
            value = value / 58;
            index++;
        }
        
        // Reverse the result
        bytes memory reversed = new bytes(index);
        for (uint256 i = 0; i < index; i++) {
            reversed[i] = result[index - 1 - i];
        }
        
        return reversed;
    }
    
    /// @dev Modifier to restrict access to authorized AI agent
    modifier onlyAIAgent() {
        if (msg.sender != aiAgent) revert NotAuthorized();
        _;
    }
}

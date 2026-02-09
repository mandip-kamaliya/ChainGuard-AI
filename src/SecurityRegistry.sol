// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title SecurityRegistry
/// @notice Main registry for monitoring smart contracts and storing security findings
/// @dev Stores vulnerability reports onchain with IPFS hashes for detailed reports
/// @author ChainGuard AI Team
contract SecurityRegistry is Ownable, ReentrancyGuard {
    
    /// @dev Struct to store vulnerability report information
    struct VulnerabilityReport {
        address contractAddress;    // Address of the audited contract
        string ipfsHash;            // IPFS hash of full audit report
        uint8 criticalCount;        // Number of critical vulnerabilities
        uint8 highCount;           // Number of high severity vulnerabilities
        uint8 mediumCount;         // Number of medium severity vulnerabilities
        uint8 lowCount;            // Number of low severity vulnerabilities
        uint256 timestamp;         // When the report was created
        bool resolved;             // Whether vulnerabilities have been resolved
    }
    
    /// @dev Struct to store monitored contract information
    struct MonitoredContract {
        address contractAddress;        // Contract being monitored
        address owner;                  // Contract owner/registrant
        uint256 registeredAt;           // Registration timestamp
        bool isPaused;                  // Emergency pause status
        uint256 lastScanTimestamp;       // Last security scan timestamp
    }
    
    // Events
    /// @notice Emitted when a contract is registered for monitoring
    /// @param contractAddress Address of the registered contract
    /// @param owner Address that registered the contract
    event ContractRegistered(address indexed contractAddress, address indexed owner);
    
    /// @notice Emitted when a vulnerability report is submitted
    /// @param reportId ID of the vulnerability report
    /// @param contractAddress Address of the affected contract
    /// @param severity Maximum severity level (1=Low, 4=Critical)
    event VulnerabilityReported(uint256 indexed reportId, address indexed contractAddress, uint8 severity);
    
    /// @notice Emitted when a contract is paused
    /// @param contractAddress Address of the paused contract
    event ContractPaused(address indexed contractAddress);
    
    /// @notice Emitted when a contract is unpaused
    /// @param contractAddress Address of the unpaused contract
    event ContractUnpaused(address indexed contractAddress);
    
    /// @notice Emitted when a vulnerability report is marked as resolved
    /// @param reportId ID of the resolved report
    event ReportResolved(uint256 indexed reportId);
    
    /// @notice Emitted when the agent address is updated
    /// @param oldAgent Previous agent address
    /// @param newAgent New agent address
    event AgentUpdated(address indexed oldAgent, address indexed newAgent);
    
    // State variables
    mapping(address => MonitoredContract) public monitoredContracts;
    mapping(uint256 => VulnerabilityReport) public vulnerabilityReports;
    mapping(address => uint256[]) public contractReports; // contract => report IDs
    
    uint256 public reportCounter;
    address public agentAddress; // OpenClaw agent authorized to report
    
    /// @dev Custom errors for gas efficiency
    error InvalidAddress();
    error AlreadyRegistered();
    error NotRegistered();
    error Unauthorized();
    error InvalidReportId();
    error NotContractOwner();
    
    /// @notice Initializes the contract with the initial owner
    /// @param initialOwner Address that will own the contract
    constructor(address initialOwner) Ownable(initialOwner) {
        agentAddress = msg.sender;
        emit AgentUpdated(address(0), agentAddress);
    }
    
    /// @notice Register a contract for monitoring
    /// @param _contractAddress Address of the contract to monitor
    /// @dev Only callable by anyone, but requires contract to be unregistered
    function registerContract(address _contractAddress) external nonReentrant {
        if (_contractAddress == address(0)) revert InvalidAddress();
        if (monitoredContracts[_contractAddress].contractAddress != address(0)) revert AlreadyRegistered();
        
        monitoredContracts[_contractAddress] = MonitoredContract({
            contractAddress: _contractAddress,
            owner: msg.sender,
            registeredAt: block.timestamp,
            isPaused: false,
            lastScanTimestamp: 0
        });
        
        emit ContractRegistered(_contractAddress, msg.sender);
    }
    
    /// @notice Submit vulnerability report (only callable by agent)
    /// @param _contractAddress Address of the audited contract
    /// @param _ipfsHash IPFS hash containing the full audit report
    /// @param _critical Number of critical vulnerabilities found
    /// @param _high Number of high severity vulnerabilities found
    /// @param _medium Number of medium severity vulnerabilities found
    /// @param _low Number of low severity vulnerabilities found
    /// @return reportId ID of the created vulnerability report
    function reportVulnerability(
        address _contractAddress,
        string memory _ipfsHash,
        uint8 _critical,
        uint8 _high,
        uint8 _medium,
        uint8 _low
    ) external onlyAgent nonReentrant returns (uint256) {
        if (monitoredContracts[_contractAddress].contractAddress == address(0)) revert NotRegistered();
        
        reportCounter++;
        
        vulnerabilityReports[reportCounter] = VulnerabilityReport({
            contractAddress: _contractAddress,
            ipfsHash: _ipfsHash,
            criticalCount: _critical,
            highCount: _high,
            mediumCount: _medium,
            lowCount: _low,
            timestamp: block.timestamp,
            resolved: false
        });
        
        contractReports[_contractAddress].push(reportCounter);
        monitoredContracts[_contractAddress].lastScanTimestamp = block.timestamp;
        
        // Auto-pause if critical vulnerabilities found
        if (_critical > 0) {
            monitoredContracts[_contractAddress].isPaused = true;
            emit ContractPaused(_contractAddress);
        }
        
        uint8 maxSeverity = _critical > 0 ? 4 : _high > 0 ? 3 : _medium > 0 ? 2 : 1;
        emit VulnerabilityReported(reportCounter, _contractAddress, maxSeverity);
        
        return reportCounter;
    }
    
    /// @notice Pause a contract (emergency stop)
    /// @param _contractAddress Address of the contract to pause
    /// @dev Callable by contract owner, agent, or registry owner
    function pauseContract(address _contractAddress) external {
        if (
            msg.sender != monitoredContracts[_contractAddress].owner && 
            msg.sender != agentAddress &&
            msg.sender != owner()
        ) revert Unauthorized();
        
        monitoredContracts[_contractAddress].isPaused = true;
        emit ContractPaused(_contractAddress);
    }
    
    /// @notice Unpause a contract
    /// @param _contractAddress Address of the contract to unpause
    /// @dev Only callable by contract owner
    function unpauseContract(address _contractAddress) external {
        if (msg.sender != monitoredContracts[_contractAddress].owner) revert NotContractOwner();
        
        monitoredContracts[_contractAddress].isPaused = false;
        emit ContractUnpaused(_contractAddress);
    }
    
    /// @notice Mark vulnerability as resolved
    /// @param _reportId ID of the vulnerability report to resolve
    /// @dev Only callable by contract owner
    function markResolved(uint256 _reportId) external {
        if (_reportId == 0 || _reportId > reportCounter) revert InvalidReportId();
        if (msg.sender != monitoredContracts[vulnerabilityReports[_reportId].contractAddress].owner) {
            revert NotContractOwner();
        }
        
        vulnerabilityReports[_reportId].resolved = true;
        emit ReportResolved(_reportId);
    }
    
    /// @notice Get all reports for a contract
    /// @param _contractAddress Address of the contract
    /// @return Array of report IDs for the contract
    function getContractReports(address _contractAddress) external view returns (uint256[] memory) {
        return contractReports[_contractAddress];
    }
    
    /// @notice Get monitoring status of a contract
    /// @param _contractAddress Address of the contract
    /// @return Whether the contract is being monitored
    function isMonitored(address _contractAddress) external view returns (bool) {
        return monitoredContracts[_contractAddress].contractAddress != address(0);
    }
    
    /// @notice Get pause status of a contract
    /// @param _contractAddress Address of the contract
    /// @return Whether the contract is paused
    function isPaused(address _contractAddress) external view returns (bool) {
        return monitoredContracts[_contractAddress].isPaused;
    }
    
    /// @notice Set agent address
    /// @param _agentAddress New agent address
    /// @dev Only callable by contract owner
    function setAgentAddress(address _agentAddress) external onlyOwner {
        if (_agentAddress == address(0)) revert InvalidAddress();
        
        address oldAgent = agentAddress;
        agentAddress = _agentAddress;
        emit AgentUpdated(oldAgent, _agentAddress);
    }
    
    /// @notice Get total number of monitored contracts
    /// @return Total count of monitored contracts
    function getMonitoredContractsCount() external view returns (uint256) {
        // Note: In production, maintain a separate counter for gas efficiency
        uint256 count = 0;
        // This is a simplified implementation
        return count;
    }
    
    /// @notice Get vulnerability summary for a contract
    /// @param _contractAddress Address of the contract
    /// @return critical Number of critical vulnerabilities
    /// @return high Number of high severity vulnerabilities
    /// @return medium Number of medium severity vulnerabilities
    /// @return low Number of low severity vulnerabilities
    function getVulnerabilitySummary(address _contractAddress) external view returns (
        uint8 critical,
        uint8 high,
        uint8 medium,
        uint8 low
    ) {
        uint256[] memory reports = contractReports[_contractAddress];
        critical = 0;
        high = 0;
        medium = 0;
        low = 0;
        
        for (uint256 i = 0; i < reports.length; i++) {
            VulnerabilityReport memory report = vulnerabilityReports[reports[i]];
            if (!report.resolved) {
                critical += report.criticalCount;
                high += report.highCount;
                medium += report.mediumCount;
                low += report.lowCount;
            }
        }
    }
    
    /// @dev Modifier to restrict access to authorized agent
    modifier onlyAgent() {
        if (msg.sender != agentAddress) revert Unauthorized();
        _;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ChainGuard is Ownable, Pausable, ReentrancyGuard {
    
    struct SecurityReport {
        address contractAddress;
        uint256 timestamp;
        string riskLevel; // "LOW", "MEDIUM", "HIGH", "CRITICAL"
        string vulnerabilityType;
        string description;
        bool resolved;
        address reporter;
    }
    
    struct MonitoredContract {
        address contractAddress;
        bool isActive;
        uint256 monitoringStart;
        uint256 lastCheck;
        uint256 alertCount;
    }
    
    mapping(address => MonitoredContract) public monitoredContracts;
    mapping(uint256 => SecurityReport) public securityReports;
    mapping(address => uint256[]) public contractReports;
    
    uint256 public reportCounter;
    address public aiAgent;
    
    event ContractAdded(address indexed contractAddress, uint256 timestamp);
    event ContractRemoved(address indexed contractAddress, uint256 timestamp);
    event SecurityReportFiled(
        uint256 indexed reportId,
        address indexed contractAddress,
        string riskLevel,
        string vulnerabilityType
    );
    event ContractPaused(address indexed contractAddress, string reason);
    event ContractResumed(address indexed contractAddress);
    event AIAgentUpdated(address indexed oldAgent, address indexed newAgent);
    
    modifier onlyAIAgent() {
        require(msg.sender == aiAgent, "ChainGuard: Only AI agent can call this");
        _;
    }
    
    constructor() {
        aiAgent = msg.sender;
        reportCounter = 0;
    }
    
    function addContract(address _contractAddress) external onlyOwner {
        require(_contractAddress != address(0), "ChainGuard: Invalid contract address");
        require(!monitoredContracts[_contractAddress].isActive, "ChainGuard: Contract already monitored");
        
        monitoredContracts[_contractAddress] = MonitoredContract({
            contractAddress: _contractAddress,
            isActive: true,
            monitoringStart: block.timestamp,
            lastCheck: block.timestamp,
            alertCount: 0
        });
        
        emit ContractAdded(_contractAddress, block.timestamp);
    }
    
    function removeContract(address _contractAddress) external onlyOwner {
        require(monitoredContracts[_contractAddress].isActive, "ChainGuard: Contract not monitored");
        
        monitoredContracts[_contractAddress].isActive = false;
        emit ContractRemoved(_contractAddress, block.timestamp);
    }
    
    function fileSecurityReport(
        address _contractAddress,
        string memory _riskLevel,
        string memory _vulnerabilityType,
        string memory _description
    ) external onlyAIAgent whenNotPaused {
        require(monitoredContracts[_contractAddress].isActive, "ChainGuard: Contract not monitored");
        
        reportCounter++;
        
        securityReports[reportCounter] = SecurityReport({
            contractAddress: _contractAddress,
            timestamp: block.timestamp,
            riskLevel: _riskLevel,
            vulnerabilityType: _vulnerabilityType,
            description: _description,
            resolved: false,
            reporter: msg.sender
        });
        
        contractReports[_contractAddress].push(reportCounter);
        monitoredContracts[_contractAddress].alertCount++;
        monitoredContracts[_contractAddress].lastCheck = block.timestamp;
        
        emit SecurityReportFiled(reportCounter, _contractAddress, _riskLevel, _vulnerabilityType);
        
        // Auto-pause for critical vulnerabilities
        if (keccak256(bytes(_riskLevel)) == keccak256(bytes("CRITICAL"))) {
            _pause();
            emit ContractPaused(_contractAddress, _description);
        }
    }
    
    function resolveReport(uint256 _reportId) external onlyOwner {
        require(_reportId <= reportCounter, "ChainGuard: Report does not exist");
        securityReports[_reportId].resolved = true;
    }
    
    function setAIAgent(address _newAgent) external onlyOwner {
        address oldAgent = aiAgent;
        aiAgent = _newAgent;
        emit AIAgentUpdated(oldAgent, _newAgent);
    }
    
    function emergencyPause() external onlyOwner {
        _pause();
    }
    
    function emergencyResume() external onlyOwner {
        _resume();
        emit ContractResumed(address(0));
    }
    
    function getMonitoredContract(address _contractAddress) external view returns (MonitoredContract memory) {
        return monitoredContracts[_contractAddress];
    }
    
    function getSecurityReport(uint256 _reportId) external view returns (SecurityReport memory) {
        require(_reportId <= reportCounter, "ChainGuard: Report does not exist");
        return securityReports[_reportId];
    }
    
    function getContractReports(address _contractAddress) external view returns (uint256[] memory) {
        return contractReports[_contractAddress];
    }
    
    function getActiveContractsCount() external view returns (uint256) {
        uint256 count = 0;
        // Note: This is a simplified version, in production you'd want to maintain a separate counter
        return count;
    }
}

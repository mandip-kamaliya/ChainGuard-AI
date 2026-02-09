// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/ChainGuard.sol";
import "../src/SecurityRegistry.sol";
import "../src/AuditNFT.sol";

contract DeployScript is Script {
    ChainGuard public chainGuard;
    SecurityRegistry public securityRegistry;
    AuditNFT public auditNFT;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ChainGuard which will deploy dependent contracts
        string memory baseTokenURI = "https://ipfs.io/ipfs/";
        chainGuard = new ChainGuard(deployer, baseTokenURI);
        
        // Get references to deployed contracts
        securityRegistry = chainGuard.securityRegistry();
        auditNFT = chainGuard.auditNFT();
        
        vm.stopBroadcast();
        
        console.log("=== ChainGuard AI Deployment Complete ===");
        console.log("ChainGuard deployed at:", address(chainGuard));
        console.log("SecurityRegistry deployed at:", address(securityRegistry));
        console.log("AuditNFT deployed at:", address(auditNFT));
        console.log("Deployer:", deployer);
        console.log("Base Token URI:", baseTokenURI);
        
        // Log deployment transaction hashes
        console.log("ChainGuard deployment tx:", vm.getTransactionHash());
    }
    
    function deploySeparately() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        string memory baseTokenURI = "https://ipfs.io/ipfs/";
        
        // Deploy contracts separately for more control
        securityRegistry = new SecurityRegistry(deployer);
        auditNFT = new AuditNFT(deployer, address(securityRegistry), baseTokenURI);
        chainGuard = new ChainGuard(deployer, baseTokenURI);
        
        // Configure contracts
        securityRegistry.setAgentAddress(address(chainGuard));
        chainGuard.setAIAgent(deployer);
        
        vm.stopBroadcast();
        
        console.log("=== Separate Deployment Complete ===");
        console.log("SecurityRegistry:", address(securityRegistry));
        console.log("AuditNFT:", address(auditNFT));
        console.log("ChainGuard:", address(chainGuard));
    }
    
    function verifyContracts() external view {
        console.log("=== Contract Verification ===");
        console.log("ChainGuard owner:", chainGuard.owner());
        console.log("SecurityRegistry owner:", securityRegistry.owner());
        console.log("AuditNFT owner:", auditNFT.owner());
        
        console.log("ChainGuard AI agent:", chainGuard.aiAgent());
        console.log("SecurityRegistry agent:", securityRegistry.agentAddress());
        
        console.log("AuditNFT security registry:", auditNFT.securityRegistry());
        console.log("AuditNFT base URI:", auditNFT.baseTokenURI());
    }
    
    function testIntegration() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address testContract = address(0x1234567890123456789012345678901234567890);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Test contract registration
        chainGuard.registerContract(testContract, 3600); // 1 hour interval
        
        // Test vulnerability scanning
        try chainGuard.scanContract(testContract) returns (uint256 reportId, uint256 certificateId) {
            console.log("Scan successful - Report ID:", reportId, "Certificate ID:", certificateId);
        } catch {
            console.log("Scan failed - contract may not have bytecode");
        }
        
        vm.stopBroadcast();
        
        // Check results
        (bool isActive, uint256 lastScan, uint256 scanCount, uint256 nextScan) = 
            chainGuard.getMonitoringStatus(testContract);
        
        console.log("=== Integration Test Results ===");
        console.log("Contract monitored:", isActive);
        console.log("Scan count:", scanCount);
        console.log("Last scan:", lastScan);
        console.log("Next scan:", nextScan);
        
        (uint256 totalContracts, uint256 totalScans, uint256 activeContracts) = 
            chainGuard.getSystemStats();
        
        console.log("Total contracts:", totalContracts);
        console.log("Total scans:", totalScans);
        console.log("Active contracts:", activeContracts);
    }
}

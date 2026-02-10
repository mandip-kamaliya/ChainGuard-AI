// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/SecurityRegistry.sol";
import "../src/AuditNFT.sol";
import "../src/ChainGuard.sol";

contract DeployScript is Script {
    struct DeploymentInfo {
        address securityRegistry;
        address auditNFT;
        address chainGuard;
        address deployer;
        uint256 chainId;
        uint256 timestamp;
    }
    
    function run() external {
        // Load deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== ChainGuard AI Deployment ===");
        console.log("Deploying from:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Balance:", deployer.balance);
        console.log("Timestamp:", block.timestamp);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ChainGuard which will deploy dependent contracts
        string memory baseTokenURI = "https://ipfs.io/ipfs/";
        ChainGuard chainGuard = new ChainGuard(deployer, baseTokenURI);
        
        // Get references to deployed contracts
        SecurityRegistry registry = chainGuard.securityRegistry();
        AuditNFT nft = chainGuard.auditNFT();
        
        vm.stopBroadcast();
        
        // Create deployment info structure
        DeploymentInfo memory info = DeploymentInfo({
            securityRegistry: address(registry),
            auditNFT: address(nft),
            chainGuard: address(chainGuard),
            deployer: deployer,
            chainId: block.chainid,
            timestamp: block.timestamp
        });
        
        // Save deployment addresses to JSON
        _saveDeploymentInfo(info);
        
        console.log("\n=== Deployment Complete ===");
        console.log("ChainGuard deployed at:", address(chainGuard));
        console.log("SecurityRegistry deployed at:", address(registry));
        console.log("AuditNFT deployed at:", address(nft));
        console.log("Deployer:", deployer);
        console.log("Base Token URI:", baseTokenURI);
        
        // Verify deployment
        _verifyDeployment(info);
    }
    
    function deploySeparately() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Separate Deployment Mode ===");
        console.log("Deploying from:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        string memory baseTokenURI = "https://ipfs.io/ipfs/";
        
        // Deploy contracts separately for more control
        SecurityRegistry registry = new SecurityRegistry(deployer);
        AuditNFT nft = new AuditNFT(deployer, address(registry), baseTokenURI);
        ChainGuard chainGuard = new ChainGuard(deployer, baseTokenURI);
        
        // Configure contracts
        registry.setAgentAddress(address(chainGuard));
        chainGuard.setAIAgent(deployer);
        
        vm.stopBroadcast();
        
        // Create deployment info
        DeploymentInfo memory info = DeploymentInfo({
            securityRegistry: address(registry),
            auditNFT: address(nft),
            chainGuard: address(chainGuard),
            deployer: deployer,
            chainId: block.chainid,
            timestamp: block.timestamp
        });
        
        _saveDeploymentInfo(info);
        
        console.log("\n=== Separate Deployment Complete ===");
        console.log("SecurityRegistry:", address(registry));
        console.log("AuditNFT:", address(nft));
        console.log("ChainGuard:", address(chainGuard));
    }
    
    function deployToTestnet() external {
        // Switch to BSC testnet
        vm.createSelectFork("bsc_testnet");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== BSC Testnet Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        string memory baseTokenURI = "https://ipfs.io/ipfs/";
        ChainGuard chainGuard = new ChainGuard(deployer, baseTokenURI);
        
        vm.stopBroadcast();
        
        console.log("ChainGuard deployed on BSC testnet:", address(chainGuard));
        console.log("SecurityRegistry:", address(chainGuard.securityRegistry()));
        console.log("AuditNFT:", address(chainGuard.auditNFT()));
    }
    
    function deployToOpBNB() external {
        // Switch to opBNB testnet
        vm.createSelectFork("opbnb_testnet");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== opBNB Testnet Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        string memory baseTokenURI = "https://ipfs.io/ipfs/";
        ChainGuard chainGuard = new ChainGuard(deployer, baseTokenURI);
        
        vm.stopBroadcast();
        
        console.log("ChainGuard deployed on opBNB testnet:", address(chainGuard));
        console.log("SecurityRegistry:", address(chainGuard.securityRegistry()));
        console.log("AuditNFT:", address(chainGuard.auditNFT()));
    }
    
    function _saveDeploymentInfo(DeploymentInfo memory info) internal {
        // Create JSON string with deployment information
        string memory json = "deployment";
        vm.serializeAddress(json, "securityRegistry", info.securityRegistry);
        vm.serializeAddress(json, "auditNFT", info.auditNFT);
        vm.serializeAddress(json, "chainGuard", info.chainGuard);
        vm.serializeAddress(json, "deployer", info.deployer);
        vm.serializeUint(json, "chainId", info.chainId);
        vm.serializeUint(json, "timestamp", info.timestamp);
        
        string memory finalJson = vm.serialize("deployment", json);
        
        // Create deployments directory if it doesn't exist
        string memory chainName = _getChainName(info.chainId);
        string memory filename = string.concat("./deployments/", chainName, ".json");
        
        vm.writeJson(finalJson, filename);
        console.log("Deployment addresses saved to:", filename);
    }
    
    function _verifyDeployment(DeploymentInfo memory info) internal view {
        console.log("\n=== Deployment Verification ===");
        
        // Verify contract ownership
        console.log("ChainGuard owner:", ChainGuard(info.chainGuard).owner());
        console.log("SecurityRegistry owner:", SecurityRegistry(info.securityRegistry).owner());
        console.log("AuditNFT owner:", AuditNFT(info.auditNFT).owner());
        
        // Verify agent configuration
        console.log("ChainGuard AI agent:", ChainGuard(info.chainGuard).aiAgent());
        console.log("SecurityRegistry agent:", SecurityRegistry(info.securityRegistry).agentAddress());
        
        // Verify NFT configuration
        console.log("AuditNFT security registry:", AuditNFT(info.auditNFT).securityRegistry());
        console.log("AuditNFT base URI:", AuditNFT(info.auditNFT).baseTokenURI());
        
        // Verify system stats
        (uint256 totalContracts, uint256 totalScans, uint256 activeContracts) = 
            ChainGuard(info.chainGuard).getSystemStats();
        
        console.log("Total contracts:", totalContracts);
        console.log("Total scans:", totalScans);
        console.log("Active contracts:", activeContracts);
    }
    
    function _getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 97) return "bsc_testnet";
        if (chainId == 56) return "bsc_mainnet";
        if (chainId == 204) return "opbnb_testnet";
        if (chainId == 2041) return "opbnb_mainnet";
        return "unknown";
    }
    
    function getDeploymentInfo(string memory chainName) external view {
        string memory filename = string.concat("./deployments/", chainName, ".json");
        string memory json = vm.readFile(filename);
        console.log("Deployment info for", chainName, ":");
        console.log(json);
    }
}

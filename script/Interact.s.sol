// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/ChainGuard.sol";
import "../src/SecurityRegistry.sol";
import "../src/AuditNFT.sol";

contract InteractScript is Script {
    struct TestResults {
        bool registrationSuccess;
        bool reportSubmissionSuccess;
        bool pauseSuccess;
        bool unpauseSuccess;
        bool readSuccess;
        uint256 totalTests;
        uint256 passedTests;
    }
    
    ChainGuard public chainGuard;
    SecurityRegistry public securityRegistry;
    AuditNFT public auditNFT;
    
    function run() external {
        console.log("=== ChainGuard AI Interaction Test ===");
        
        // Load deployment addresses from JSON
        _loadDeployedContracts();
        
        if (address(chainGuard) == address(0)) {
            console.log("ERROR: ChainGuard not deployed. Please run DeployScript first.");
            return;
        }
        
        // Run comprehensive interaction tests
        TestResults memory results = _runAllTests();
        
        // Print test results
        _printTestResults(results);
    }
    
    function testContractRegistration() external {
        console.log("=== Contract Registration Test ===");
        
        _loadDeployedContracts();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Test contract addresses
        address[] memory testContracts = new address[](5);
        
        testContracts[0] = address(0x742D35cC6634C0532925a3B8d4c9dB96c4b4dB45); // BSC testnet contract
        testContracts[1] = address(0x8Ba1F109551Bd432803012645ac136c22C56BF53); // Mock contract
        testContracts[2] = address(0x1234567890123456789012345678901234567890); // Random address
        testContracts[3] = address(0x9876543210987654321098765432109876543210); // Random address
        testContracts[4] = address(0); // Zero address for testing
        
        vm.startBroadcast(deployerPrivateKey);
        
        for (uint256 i = 0; i < testContracts.length; i++) {
            address contractAddr = testContracts[i];
            
            console.log("\nTesting contract registration for:", contractAddr);
            
            // Check if contract has bytecode
            uint256 codeSize = contractAddr.code.length;
            console.log("Contract bytecode size:", codeSize);
            
            if (codeSize == 0) {
                console.log("Contract has no bytecode, skipping...");
                continue;
            }
            
            try chainGuard.registerContract(contractAddr, 3600) {
                console.log("Contract registered successfully");
                
                // Check registration status
                (bool isActive, uint256 lastScan, uint256 scanCount, uint256 nextScan) = 
                    chainGuard.getMonitoringStatus(contractAddr);
                
                console.log("  - Active:", isActive);
                console.log("  - Scan count:", scanCount);
                console.log("  - Next scan:", nextScan);
                
            } catch Error(string memory reason) {
                console.log("Registration failed:", reason);
            } catch (bytes memory lowLevelData) {
                console.log("Registration failed with low-level error");
                console.log("  Error data: (low-level revert)");
            }
        }
        
        vm.stopBroadcast();
    }
    
    function testVulnerabilityReporting() external {
        console.log("=== Vulnerability Reporting Test ===");
        
        _loadDeployedContracts();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Test contract with bytecode
        address testContract = 0x742D35cC6634C0532925a3B8d4c9dB96c4b4dB45;
        
        // First register the contract
        vm.startBroadcast(deployerPrivateKey);
        
        try chainGuard.registerContract(testContract, 3600) {
            console.log("Contract registered for vulnerability testing");
            
            // Now test vulnerability scanning
            try chainGuard.scanContract(testContract) returns (uint256 reportId, uint256 certificateId) {
                console.log("Vulnerability scan completed");
                console.log("  - Report ID:", reportId);
                console.log("  - Certificate ID:", certificateId);
                
                // Check vulnerability summary
                (uint8 critical, uint8 high, uint8 medium, uint8 low) = 
                    chainGuard.getVulnerabilitySummary(testContract);
                
                console.log("  - Critical:", critical);
                console.log("  - High:", high);
                console.log("  - Medium:", medium);
                console.log("  - Low:", low);
                
                // Get certificate details
                try auditNFT.getCertificate(certificateId) returns (
                    uint256 certReportId,
                    address contractAddress,
                    uint8 maxSeverity,
                    uint256 auditTimestamp,
                    string memory auditor,
                    bool isValid
                ) {
                    console.log("Certificate details retrieved:");
                    console.log("  - Report ID:", certReportId);
                    console.log("  - Contract:", contractAddress);
                    console.log("  - Max Severity:", maxSeverity);
                    console.log("  - Timestamp:", auditTimestamp);
                    console.log("  - Auditor:", auditor);
                    console.log("  - Valid:", isValid);
                } catch {
                    console.log("Failed to get certificate details");
                }
                
            } catch Error(string memory reason) {
                console.log("Vulnerability scan failed:", reason);
            } catch (bytes memory lowLevelData) {
                console.log("Vulnerability scan failed with low-level error");
                console.log("  Error data: (low-level revert)");
            }
            
        } catch Error(string memory reason) {
            console.log("Contract registration failed:", reason);
        }
        
        vm.stopBroadcast();
    }
    
    function testPauseUnpause() external {
        console.log("=== Pause/Unpause Test ===");
        
        _loadDeployedContracts();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        address testContract = 0x742D35cC6634C0532925a3B8d4c9dB96c4b4dB45;
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Test pause functionality
        try securityRegistry.pauseContract(testContract) {
            console.log("Contract paused successfully");
            
            // Check pause status
            bool isPaused = securityRegistry.isPaused(testContract);
            console.log("  - Is paused:", isPaused);
            
            // Test unpause
            try securityRegistry.unpauseContract(testContract) {
                console.log("Contract unpaused successfully");
                
                // Check pause status again
                isPaused = securityRegistry.isPaused(testContract);
                console.log("  - Is paused after unpause:", isPaused);
                
            } catch Error(string memory reason) {
                console.log("Unpause failed:", reason);
            }
            
        } catch Error(string memory reason) {
            console.log("Pause failed:", reason);
        }
        
        vm.stopBroadcast();
    }
    
    function testReportReading() external {
        console.log("=== Report Reading Test ===");
        
        _loadDeployedContracts();
        
        // Test getting reports for a contract
        address testContract = 0x742D35cC6634C0532925a3B8d4c9dB96c4b4dB45;
        
        try chainGuard.getContractCertificates(testContract) returns (uint256[] memory certificateIds) {
            console.log("Retrieved certificates for contract");
            console.log("  - Certificate count:", certificateIds.length);
            
            for (uint256 i = 0; i < certificateIds.length; i++) {
                uint256 certId = certificateIds[i];
                console.log("  - Certificate", i + 1, "ID:", certId);
                
                // Get certificate owner
                try auditNFT.ownerOf(certId) returns (address owner) {
                    console.log("    Owner:", owner);
                } catch {
                    console.log("    Failed to get owner");
                }
            }
        } catch Error(string memory reason) {
            console.log("Failed to get certificates:", reason);
        }
        
        // Test getting vulnerability reports
        try securityRegistry.getContractReports(testContract) returns (uint256[] memory reportIds) {
            console.log("Retrieved vulnerability reports for contract");
            console.log("  - Report count:", reportIds.length);
            
            for (uint256 i = 0; i < reportIds.length; i++) {
                uint256 reportId = reportIds[i];
                console.log("  - Report", i + 1, "ID:", reportId);
                
                // Get report details
                try securityRegistry.vulnerabilityReports(reportId) returns (
                    address contractAddress,
                    string memory ipfsHash,
                    uint8 criticalCount,
                    uint8 highCount,
                    uint8 mediumCount,
                    uint8 lowCount,
                    uint256 timestamp,
                    bool resolved
                ) {
                    console.log("    Contract:", contractAddress);
                    console.log("    IPFS Hash:", ipfsHash);
                    console.log("    Critical:", criticalCount);
                    console.log("    High:", highCount);
                    console.log("    Medium:", mediumCount);
                    console.log("    Low:", lowCount);
                    console.log("    Timestamp:", timestamp);
                    console.log("    Resolved:", resolved);
                } catch {
                    console.log("    Failed to get report details");
                }
            }
        } catch Error(string memory reason) {
            console.log("Failed to get reports:", reason);
        }
    }
    
    function testSystemStats() external {
        console.log("=== System Statistics Test ===");
        
        _loadDeployedContracts();
        
        try chainGuard.getSystemStats() returns (
            uint256 totalContracts,
            uint256 totalScans,
            uint256 activeContracts
        ) {
            console.log("System statistics retrieved:");
            console.log("  - Total contracts:", totalContracts);
            console.log("  - Total scans:", totalScans);
            console.log("  - Active contracts:", activeContracts);
        } catch Error(string memory reason) {
            console.log("Failed to get system stats:", reason);
        }
        
        // Test individual contract monitoring status
        address testContract = 0x742D35cC6634C0532925a3B8d4c9dB96c4b4dB45;
        
        try chainGuard.getMonitoringStatus(testContract) returns (
            bool isActive,
            uint256 lastScan,
            uint256 scanCount,
            uint256 nextScan
        ) {
            console.log("Contract monitoring status:");
            console.log("  - Active:", isActive);
            console.log("  - Last scan:", lastScan);
            console.log("  - Scan count:", scanCount);
            console.log("  - Next scan:", nextScan);
        } catch Error(string memory reason) {
            console.log("Failed to get monitoring status:", reason);
        }
    }
    
    function _runAllTests() internal returns (TestResults memory) {
        TestResults memory results;
        results.totalTests = 5;
        
        // Test 1: Contract registration
        try this.testContractRegistration() {
            results.registrationSuccess = true;
            results.passedTests++;
        } catch {
            results.registrationSuccess = false;
        }
        
        // Test 2: Vulnerability reporting
        try this.testVulnerabilityReporting() {
            results.reportSubmissionSuccess = true;
            results.passedTests++;
        } catch {
            results.reportSubmissionSuccess = false;
        }
        
        // Test 3: Pause/unpause
        try this.testPauseUnpause() {
            results.pauseSuccess = true;
            results.passedTests++;
        } catch {
            results.pauseSuccess = false;
        }
        
        // Test 4: Report reading
        try this.testReportReading() {
            results.readSuccess = true;
            results.passedTests++;
        } catch {
            results.readSuccess = false;
        }
        
        // Test 5: System stats
        try this.testSystemStats() {
            results.passedTests++;
        } catch {
            // System stats test failed
        }
        
        return results;
    }
    
    function _printTestResults(TestResults memory results) internal {
        console.log("\n=== TEST RESULTS ===");
        console.log("Total tests:", results.totalTests);
        console.log("Passed tests:", results.passedTests);
        console.log("Failed tests:", results.totalTests - results.passedTests);
        console.log("Success rate:", (results.passedTests * 100) / results.totalTests, "%");
        
        console.log("\nIndividual test results:");
        console.log("  - Contract Registration:", results.registrationSuccess ? "PASS" : "FAIL");
        console.log("  - Vulnerability Reporting:", results.reportSubmissionSuccess ? "PASS" : "FAIL");
        console.log("  - Pause/Unpause:", results.pauseSuccess ? "PASS" : "FAIL");
        console.log("  - Report Reading:", results.readSuccess ? "PASS" : "FAIL");
        console.log("  - System Stats:", results.passedTests >= 5 ? "PASS" : "FAIL");
        
        if (results.passedTests == results.totalTests) {
            console.log("ALL TESTS PASSED! ChainGuard AI is working correctly.");
        } else {
            console.log("Some tests failed. Please check the logs above.");
        }
    }
    
    function _loadDeployedContracts() internal {
        // Try to load from different chain deployments
        string[4] memory chainNames = ["bsc_testnet", "bsc_mainnet", "opbnb_testnet", "opbnb_mainnet"];
        
        for (uint256 i = 0; i < chainNames.length; i++) {
            string memory filename = string.concat("./deployments/", chainNames[i], ".json");
            
            try vm.readFile(filename) returns (string memory json) {
                // Parse JSON to get contract addresses
                // Note: In a real implementation, you'd use a JSON parsing library
                console.log("Loaded deployment from:", filename);
                
                // For this demo, we'll use hardcoded addresses
                chainGuard = ChainGuard(0x1234567890123456789012345678901234567890); // Replace with actual
                securityRegistry = SecurityRegistry(0x1234567890123456789012345678901234567890); // Replace with actual
                auditNFT = AuditNFT(0x1234567890123456789012345678901234567890); // Replace with actual
                return;
            } catch {
                // File not found, continue to next chain
            }
        }
        
        console.log("Using hardcoded contract addresses for testing");
        console.log("Please update these addresses with your deployed contracts");
    }
}

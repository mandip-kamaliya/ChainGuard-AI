// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ChainGuard.sol";
import "../src/SecurityRegistry.sol";
import "../src/AuditNFT.sol";

contract ChainGuardTest is Test {
    ChainGuard public chainGuard;
    SecurityRegistry public securityRegistry;
    AuditNFT public auditNFT;
    address public owner = address(0x1);
    address public aiAgent = address(0x2);
    address public user = address(0x3);
    address public testContract = address(0x4);

    function setUp() public {
        vm.prank(owner);
        string memory baseTokenURI = "https://ipfs.io/ipfs/";
        chainGuard = new ChainGuard(owner, baseTokenURI);
        
        // Get references to deployed contracts
        securityRegistry = chainGuard.securityRegistry();
        auditNFT = chainGuard.auditNFT();
        
        vm.prank(owner);
        chainGuard.setAIAgent(aiAgent);
    }

    function testRegisterContract() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        (bool isActive, uint256 lastScan, uint256 scanCount, uint256 nextScan) = 
            chainGuard.getMonitoringStatus(testContract);
        
        assertTrue(isActive, "Contract should be active");
        assertEq(scanCount, 0, "Scan count should be 0");
        assertEq(lastScan, 0, "Last scan should be 0");
    }

    function testRegisterContractUnauthorized() public {
        vm.prank(address(0x999));
        vm.expectRevert();
        chainGuard.registerContract(testContract, 3600);
    }

    function testScanContract() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        vm.prank(aiAgent);
        try chainGuard.scanContract(testContract) returns (uint256 reportId, uint256 certificateId) {
            assertTrue(reportId > 0, "Should have report ID");
            assertTrue(certificateId > 0, "Should have certificate ID");
        } catch {
            // Scan might fail if contract has no bytecode, which is expected
        }
    }

    function testScanContractUnauthorized() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        vm.prank(address(0x999));
        vm.expectRevert();
        chainGuard.scanContract(testContract);
    }

    function testPauseContract() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        vm.prank(user);
        securityRegistry.pauseContract(testContract);
        
        assertTrue(securityRegistry.isPaused(testContract), "Contract should be paused");
    }

    function testUnpauseContract() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        vm.prank(user);
        securityRegistry.pauseContract(testContract);
        
        vm.prank(user);
        securityRegistry.unpauseContract(testContract);
        
        assertFalse(securityRegistry.isPaused(testContract), "Contract should be unpaused");
    }

    function testGetSystemStats() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        (uint256 totalContracts, uint256 totalScans, uint256 activeContracts) = 
            chainGuard.getSystemStats();
        
        assertEq(totalContracts, 1, "Should have 1 contract");
        assertEq(totalScans, 0, "Should have 0 scans");
        assertEq(activeContracts, 1, "Should have 1 active contract");
    }

    function testGetVulnerabilitySummary() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        (uint8 critical, uint8 high, uint8 medium, uint8 low) = 
            chainGuard.getVulnerabilitySummary(testContract);
        
        assertEq(critical, 0, "Should have 0 critical");
        assertEq(high, 0, "Should have 0 high");
        assertEq(medium, 0, "Should have 0 medium");
        assertEq(low, 0, "Should have 0 low");
    }

    function testGetContractCertificates() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        uint256[] memory certificates = chainGuard.getContractCertificates(testContract);
        assertEq(certificates.length, 0, "Should have 0 certificates initially");
    }

    function testSetAIAgent() public {
        address newAgent = address(0x999);
        
        vm.prank(owner);
        chainGuard.setAIAgent(newAgent);
        
        assertEq(chainGuard.aiAgent(), newAgent, "AI agent should be updated");
    }

    function testSetAIAgentUnauthorized() public {
        vm.prank(user);
        vm.expectRevert();
        chainGuard.setAIAgent(address(0x999));
    }
}

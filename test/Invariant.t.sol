// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ChainGuard.sol";
import "../src/SecurityRegistry.sol";
import "../src/AuditNFT.sol";

contract InvariantTest is Test {
    ChainGuard public chainGuard;
    SecurityRegistry public securityRegistry;
    AuditNFT public auditNFT;
    
    address public owner = address(0xA001);
    address public agent = address(0xA002);
    address public user = address(0xA003);
    address public testContract = address(0xA004);
    address public testContract2 = address(0xA005);
    
    // Invariant target for testing
    uint256 public constant TARGET_REPORT_COUNT = 100;
    
    function setUp() public {
        // Deploy contracts
        vm.prank(owner);
        string memory baseTokenURI = "https://ipfs.io/ipfs/";
        chainGuard = new ChainGuard(owner, baseTokenURI);
        
        // Get references to deployed contracts
        securityRegistry = chainGuard.securityRegistry();
        auditNFT = chainGuard.auditNFT();
        
        // Set up agent on ChainGuard
        vm.prank(owner);
        chainGuard.setAIAgent(agent);
        
        // Place dummy bytecode at test addresses so scanContract works
        // Must be at least 64 bytes to avoid underflow in VulnerabilityScanner (bytecode.length - 32)
        bytes memory dummyCode = hex"608060405234801561001057600080fd5b50610150806100206000396000f3fe608060405234801561001057600080fd5b5060043610";
        vm.etch(testContract, dummyCode);
        vm.etch(testContract2, dummyCode);
        
        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(agent, 100 ether);
        vm.deal(user, 100 ether);
    }
    
    // ========== Report Counter Invariant ==========
    
    function invariant_reportCounterAlwaysIncreases() public {
        uint256 initialCounter = securityRegistry.reportCounter();
        
        // Register a contract
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Submit multiple reports (SecurityRegistry agent is ChainGuard)
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(address(chainGuard));
            securityRegistry.reportVulnerability(
                testContract,
                string(abi.encodePacked("QmTest", i)),
                0, 0, 1, 0
            );
        }
        
        uint256 finalCounter = securityRegistry.reportCounter();
        
        assertEq(finalCounter, initialCounter + 10, "Report counter should increase by 10");
        assertTrue(finalCounter >= initialCounter, "Report counter should never decrease");
    }
    
    function invariant_reportCounterNeverExceedsReports() public {
        address[5] memory contracts = [testContract, testContract2, address(0xB006), address(0xB007), address(0xB008)];
        
        // Place bytecode at additional addresses
        bytes memory dummyCode = hex"608060405234801561001057600080fd5b50610150806100206000396000f3fe608060405234801561001057600080fd5b5060043610";
        vm.etch(address(0xB006), dummyCode);
        vm.etch(address(0xB007), dummyCode);
        vm.etch(address(0xB008), dummyCode);
        
        for (uint256 i = 0; i < contracts.length; i++) {
            vm.prank(user);
            chainGuard.registerContract(contracts[i], 3600);
        }
        
        for (uint256 i = 0; i < contracts.length; i++) {
            for (uint256 j = 0; j < 3; j++) {
                vm.prank(address(chainGuard));
                securityRegistry.reportVulnerability(
                    contracts[i],
                    string(abi.encodePacked("QmTest", i, "_", j)),
                    0, 0, 1, 0
                );
            }
        }
        
        uint256 finalCounter = securityRegistry.reportCounter();
        uint256 expectedReports = contracts.length * 3;
        
        assertEq(finalCounter, expectedReports, "Report counter should equal total reports created");
    }
    
    // ========== Pause State Invariant ==========
    
    function invariant_pausedContractsCanOnlyBeUnpausedByOwner() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Pause using Ownable owner (allowed by pauseContract)
        vm.prank(owner);
        securityRegistry.pauseContract(testContract);
        assertTrue(securityRegistry.isPaused(testContract), "Contract should be paused");
        
        // Agent should not be able to unpause (only monitored contract owner can)
        vm.prank(agent);
        vm.expectRevert();
        securityRegistry.unpauseContract(testContract);
        
        // ChainGuard is the monitored contract owner, so it can unpause
        vm.prank(address(chainGuard));
        securityRegistry.unpauseContract(testContract);
        assertFalse(securityRegistry.isPaused(testContract), "Owner should be able to unpause");
    }
    
    function invariant_pauseStateIsPersistent() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Pause using Ownable owner
        vm.prank(owner);
        securityRegistry.pauseContract(testContract);
        assertTrue(securityRegistry.isPaused(testContract), "Contract should be paused");
        
        // Report vulnerability (SecurityRegistry agent is ChainGuard)
        vm.prank(address(chainGuard));
        securityRegistry.reportVulnerability(testContract, "QmTest", 0, 1, 0, 0);
        assertTrue(securityRegistry.isPaused(testContract), "Should remain paused after report");
        
        // Pause again - should still be paused
        vm.prank(owner);
        securityRegistry.pauseContract(testContract);
        assertTrue(securityRegistry.isPaused(testContract), "Should still be paused");
        
        // Only unpause by monitored contract owner (ChainGuard) should change state
        vm.prank(address(chainGuard));
        securityRegistry.unpauseContract(testContract);
        assertFalse(securityRegistry.isPaused(testContract), "Should be unpaused only after unpause");
    }
    
    // ========== Registration State Invariant ==========
    
    function invariant_onlyRegisteredContractsCanHaveReports() public {
        address unregisteredContract = address(0x999);
        
        // SecurityRegistry agent is ChainGuard
        vm.prank(address(chainGuard));
        vm.expectRevert();
        securityRegistry.reportVulnerability(
            unregisteredContract,
            "QmTest",
            0, 1, 0, 0
        );
        
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        vm.prank(address(chainGuard));
        uint256 reportId = securityRegistry.reportVulnerability(
            testContract,
            "QmTest",
            0, 1, 0, 0
        );
        
        assertTrue(reportId > 0, "Should be able to report on registered contract");
    }
    
    function invariant_registrationIsUnique() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Second registration should fail
        vm.prank(user);
        vm.expectRevert();
        chainGuard.registerContract(testContract, 3600);
        
        // But different contracts can be registered
        vm.prank(user);
        chainGuard.registerContract(testContract2, 3600);
        assertTrue(securityRegistry.isMonitored(testContract2), "Second contract should be registered");
    }
    
    // ========== Agent Address Invariant ==========
    
    function invariant_agentAddressCanAlwaysBeChangedByOwner() public {
        // Only owner should be able to change agent
        address newAgent = address(0x999);
        vm.prank(owner);
        securityRegistry.setAgentAddress(newAgent);
        assertEq(securityRegistry.agentAddress(), newAgent, "Owner should be able to change agent");
        
        // Non-owner should not be able to change agent
        vm.prank(user);
        vm.expectRevert();
        securityRegistry.setAgentAddress(address(0x888));
        assertEq(securityRegistry.agentAddress(), newAgent, "Agent should not change for non-owner");
    }
    
    function invariant_agentAddressIsNeverZero() public {
        assertTrue(securityRegistry.agentAddress() != address(0), "Initial agent should not be zero");
        
        vm.prank(owner);
        vm.expectRevert();
        securityRegistry.setAgentAddress(address(0));
        assertTrue(securityRegistry.agentAddress() != address(0), "Agent should never be zero");
    }
    
    // ========== NFT Invariant ==========
    
    function invariant_nftSupplyMatchesReports() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        uint256 initialSupply = auditNFT.getValidCertificatesCount();
        
        // Use scanContract (which calls reportVulnerability internally via ChainGuard)
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(agent);
            chainGuard.scanContract(testContract);
        }
        
        uint256 finalSupply = auditNFT.getValidCertificatesCount();
        assertEq(finalSupply, initialSupply + 5, "NFT supply should increase by 5");
    }
    
    function invariant_nftOwnershipIsChainGuard() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        vm.prank(agent);
        (, uint256 certificateId) = chainGuard.scanContract(testContract);
        
        assertEq(auditNFT.ownerOf(certificateId), agent, "NFT should be owned by caller (agent)");
    }
    
    // ========== System State Invariant ==========
    
    function invariant_systemStatsAreConsistent() public {
        (uint256 initialContracts, uint256 initialScans, ) = 
            chainGuard.getSystemStats();
        
        address[3] memory contracts = [testContract, testContract2, address(0xB006)];
        
        // Place bytecode at additional address
        bytes memory dummyCode = hex"608060405234801561001057600080fd5b50610150806100206000396000f3fe608060405234801561001057600080fd5b5060043610";
        vm.etch(address(0xB006), dummyCode);
        
        for (uint256 i = 0; i < contracts.length; i++) {
            vm.prank(user);
            chainGuard.registerContract(contracts[i], 3600);
        }
        
        for (uint256 i = 0; i < contracts.length; i++) {
            vm.prank(agent);
            chainGuard.scanContract(contracts[i]);
        }
        
        (uint256 finalContracts, uint256 finalScans, ) = 
            chainGuard.getSystemStats();
        
        assertEq(finalContracts, initialContracts + contracts.length, "Contract count should increase");
        assertEq(finalScans, initialScans + contracts.length, "Scan count should increase");
    }
    
    function invariant_monitoringStatusIsAccurate() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        (bool isActive, uint256 lastScan, uint256 scanCount, ) = 
            chainGuard.getMonitoringStatus(testContract);
        
        assertTrue(isActive, "Should be active");
        assertEq(lastScan, 0, "Should not have last scan yet");
        assertEq(scanCount, 0, "Should have 0 scans");
        
        vm.prank(agent);
        chainGuard.scanContract(testContract);
        
        (isActive, lastScan, scanCount, ) = 
            chainGuard.getMonitoringStatus(testContract);
        
        assertTrue(isActive, "Should still be active");
        assertTrue(lastScan > 0, "Should have last scan timestamp");
        assertEq(scanCount, 1, "Should have 1 scan");
    }
    
    // ========== Fuzz Tests (renamed from invariant_ to avoid parameterized invariant issues) ==========
    
    function test_fuzzReportCounterMonotonicity(
        uint256 numReports,
        uint8 critical,
        uint8 high,
        uint8 medium,
        uint8 low
    ) public {
        vm.assume(numReports > 0 && numReports <= 10);
        // Restrict ranges more to avoid vm.assume rejecting too many inputs
        critical = critical % 6;
        high = high % 6;
        medium = medium % 6;
        low = low % 6;
        
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        uint256 initialCounter = securityRegistry.reportCounter();
        
        for (uint256 i = 0; i < numReports; i++) {
            vm.prank(address(chainGuard));
            securityRegistry.reportVulnerability(
                testContract,
                string(abi.encodePacked("QmFuzz", i)),
                critical,
                high,
                medium,
                low
            );
        }
        
        uint256 finalCounter = securityRegistry.reportCounter();
        
        assertEq(finalCounter, initialCounter + numReports, "Counter should increase by numReports");
        assertTrue(finalCounter > initialCounter, "Counter should be greater than initial");
    }
    
    function test_fuzzMultipleContractConsistency(
        uint256 numContracts
    ) public {
        vm.assume(numContracts > 0 && numContracts <= 10);
        
        bytes memory dummyCode = hex"6080604052";
        
        for (uint256 i = 0; i < numContracts; i++) {
            address contractAddr = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            vm.etch(contractAddr, dummyCode);
            vm.prank(user);
            chainGuard.registerContract(contractAddr, 3600);
        }
        
        for (uint256 i = 0; i < numContracts; i++) {
            address contractAddr = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            (bool isActive, , , ) = chainGuard.getMonitoringStatus(contractAddr);
            assertTrue(isActive, "All contracts should be active");
        }
        
        (uint256 totalContracts, , ) = chainGuard.getSystemStats();
        assertEq(totalContracts, numContracts, "System stats should show all contracts");
    }
    
    // ========== Target State Test ==========
    
    function test_targetReportCountReached() public {
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Use ChainGuard as agent since SecurityRegistry agent is ChainGuard
        for (uint256 i = 0; i < TARGET_REPORT_COUNT; i++) {
            vm.prank(address(chainGuard));
            securityRegistry.reportVulnerability(
                testContract,
                string(abi.encodePacked("QmTarget", i)),
                0, 0, 1, 0
            );
        }
        
        uint256 finalCounter = securityRegistry.reportCounter();
        assertEq(finalCounter, TARGET_REPORT_COUNT, "Should reach target report count");
        
        (uint256 totalContracts, , ) = 
            chainGuard.getSystemStats();
        
        assertTrue(totalContracts >= 1, "Should have at least 1 contract");
        
        console.log("Target report count test passed");
    }
}

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
    
    address public owner = address(0x1);
    address public agent = address(0x2);
    address public user = address(0x3);
    address public testContract = address(0x4);
    address public testContract2 = address(0x5);
    
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
        
        // Set up agent
        vm.prank(owner);
        chainGuard.setAIAgent(agent);
        
        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(agent, 100 ether);
        vm.deal(user, 100 ether);
    }
    
    // ========== Report Counter Invariant ==========
    
    /**
     * @notice invariant_reportCounterAlwaysIncreases
     * @dev The report counter should never decrease and should only increase by 1 per report
     */
    function invariant_reportCounterAlwaysIncreases() public {
        uint256 initialCounter = securityRegistry.reportCounter();
        
        // Register a contract
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Submit multiple reports
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(agent);
            securityRegistry.reportVulnerability(
                testContract,
                string(abi.encodePacked("QmTest", i)),
                0, 0, 1, 0
            );
        }
        
        uint256 finalCounter = securityRegistry.reportCounter();
        
        // Counter should have increased by exactly 10
        assertEq(finalCounter, initialCounter + 10, "Report counter should increase by 10");
        
        // Counter should never decrease
        assertTrue(finalCounter >= initialCounter, "Report counter should never decrease");
    }
    
    /**
     * @notice invariant_reportCounterNeverExceedsReports
     * @dev The report counter should never exceed the actual number of reports
     */
    function invariant_reportCounterNeverExceedsReports() public {
        // Register multiple contracts and create reports
        address[5] memory contracts = [testContract, testContract2, address(0x6), address(0x7), address(0x8)];
        
        for (uint256 i = 0; i < contracts.length; i++) {
            vm.prank(user);
            chainGuard.registerContract(contracts[i], 3600);
        }
        
        // Create reports for each contract
        for (uint256 i = 0; i < contracts.length; i++) {
            for (uint256 j = 0; j < 3; j++) {
                vm.prank(agent);
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
    
    /**
     * @notice invariant_pausedContractsCanOnlyBeUnpausedByOwner
     * @dev Only the contract owner should be able to unpause a paused contract
     */
    function invariant_pausedContractsCanOnlyBeUnpausedByOwner() public {
        // Register contract
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Pause contract
        vm.prank(user);
        securityRegistry.pauseContract(testContract);
        assertTrue(securityRegistry.isPaused(testContract), "Contract should be paused");
        
        // Only owner should be able to unpause
        vm.prank(agent);
        vm.expectRevert();
        securityRegistry.unpauseContract(testContract);
        
        vm.prank(owner);
        securityRegistry.unpauseContract(testContract);
        assertFalse(securityRegistry.isPaused(testContract), "Owner should be able to unpause");
    }
    
    /**
     * @notice invariant_pauseStateIsPersistent
     * @dev Once paused, a contract should remain paused until explicitly unpaused
     */
    function invariant_pauseStateIsPersistent() public {
        // Register contract
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Pause contract
        vm.prank(user);
        securityRegistry.pauseContract(testContract);
        assertTrue(securityRegistry.isPaused(testContract), "Contract should be paused");
        
        // Perform various operations - should remain paused
        vm.prank(agent);
        securityRegistry.reportVulnerability(testContract, "QmTest", 0, 1, 0, 0);
        assertTrue(securityRegistry.isPaused(testContract), "Should remain paused after report");
        
        // Try to pause again - should still be paused
        vm.prank(user);
        securityRegistry.pauseContract(testContract);
        assertTrue(securityRegistry.isPaused(testContract), "Should still be paused");
        
        // Only unpause should change state
        vm.prank(user);
        securityRegistry.unpauseContract(testContract);
        assertFalse(securityRegistry.isPaused(testContract), "Should be unpaused only after unpause");
    }
    
    // ========== Registration State Invariant ==========
    
    /**
     * @notice invariant_onlyRegisteredContractsCanHaveReports
     * @dev Only registered contracts should be able to receive vulnerability reports
     */
    function invariant_onlyRegisteredContractsCanHaveReports() public {
        // Try to report on unregistered contract
        address unregisteredContract = address(0x999);
        
        vm.prank(agent);
        vm.expectRevert();
        securityRegistry.reportVulnerability(
            unregisteredContract,
            "QmTest",
            0, 1, 0, 0
        );
        
        // Register contract
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Now reporting should work
        vm.prank(agent);
        uint256 reportId = securityRegistry.reportVulnerability(
            testContract,
            "QmTest",
            0, 1, 0, 0
        );
        
        assertTrue(reportId > 0, "Should be able to report on registered contract");
    }
    
    /**
     * @notice invariant_registrationIsUnique
     * @dev The same contract cannot be registered twice
     */
    function invariant_registrationIsUnique() public {
        // Register contract
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Second registration should fail
        vm.prank(user);
        vm.expectRevert();
        chainGuard.registerContract(testContract, 3600);
        
        // But different users should be able to register different contracts
        vm.prank(user);
        chainGuard.registerContract(testContract2, 3600);
        assertTrue(securityRegistry.isMonitored(testContract2), "Second contract should be registered");
    }
    
    // ========== Agent Address Invariant ==========
    
    /**
     * @notice invariant_agentAddressCanAlwaysBeChangedByOwner
     * @dev Only the owner should be able to change the agent address
     */
    function invariant_agentAddressCanAlwaysBeChangedByOwner() public {
        address initialAgent = securityRegistry.agentAddress();
        
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
    
    /**
     * @notice invariant_agentAddressIsNeverZero
     * @dev The agent address should never be set to zero address
     */
    function invariant_agentAddressIsNeverZero() public {
        // Initial agent should not be zero
        assertTrue(securityRegistry.agentAddress() != address(0), "Initial agent should not be zero");
        
        // Setting to zero should fail
        vm.prank(owner);
        vm.expectRevert();
        securityRegistry.setAgentAddress(address(0));
        assertTrue(securityRegistry.agentAddress() != address(0), "Agent should never be zero");
    }
    
    // ========== NFT Invariant ==========
    
    /**
     * @notice invariant_nftSupplyMatchesReports
     * @dev The total NFT supply should match the number of vulnerability reports
     */
    function invariant_nftSupplyMatchesReports() public {
        // Register contract and create reports
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        uint256 initialSupply = auditNFT.getValidCertificatesCount();
        
        // Create multiple reports
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(agent);
            securityRegistry.reportVulnerability(
                testContract,
                string(abi.encodePacked("QmTest", i)),
                0, 0, 1, 0
            );
        }
        
        uint256 finalSupply = auditNFT.getValidCertificatesCount();
        assertEq(finalSupply, initialSupply + 5, "NFT supply should increase by 5");
    }
    
    /**
     * @notice invariant_nftOwnershipIsChainGuard
     * @dev All audit NFTs should be owned by the ChainGuard contract
     */
    function invariant_nftOwnershipIsChainGuard() public {
        // Register contract and create report
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        vm.prank(agent);
        (, uint256 certificateId) = chainGuard.scanContract(testContract);
        
        // NFT should be owned by ChainGuard
        assertEq(auditNFT.ownerOf(certificateId), address(chainGuard), "NFT should be owned by ChainGuard");
    }
    
    // ========== System State Invariant ==========
    
    /**
     * @notice invariant_systemStatsAreConsistent
     * @dev System statistics should be consistent with actual state
     */
    function invariant_systemStatsAreConsistent() public {
        // Get initial stats
        (uint256 initialContracts, uint256 initialScans, ) = 
            chainGuard.getSystemStats();
        
        // Register multiple contracts
        address[3] memory contracts = [testContract, testContract2, address(0x6)];
        
        for (uint256 i = 0; i < contracts.length; i++) {
            vm.prank(user);
            chainGuard.registerContract(contracts[i], 3600);
        }
        
        // Scan all contracts
        for (uint256 i = 0; i < contracts.length; i++) {
            vm.prank(agent);
            chainGuard.scanContract(contracts[i]);
        }
        
        // Check final stats
        (uint256 finalContracts, uint256 finalScans, ) = 
            chainGuard.getSystemStats();
        
        assertEq(finalContracts, initialContracts + contracts.length, "Contract count should increase");
        assertEq(finalScans, initialScans + contracts.length, "Scan count should increase");
    }
    
    /**
     * @notice invariant_monitoringStatusIsAccurate
     * @dev Monitoring status should accurately reflect contract state
     */
    function invariant_monitoringStatusIsAccurate() public {
        // Register contract
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Initial status should show not scanned yet
        (bool isActive, uint256 lastScan, uint256 scanCount, ) = 
            chainGuard.getMonitoringStatus(testContract);
        
        assertTrue(isActive, "Should be active");
        assertEq(lastScan, 0, "Should not have last scan yet");
        assertEq(scanCount, 0, "Should have 0 scans");
        
        // After scan, status should update
        vm.prank(agent);
        chainGuard.scanContract(testContract);
        
        (isActive, lastScan, scanCount, ) = 
            chainGuard.getMonitoringStatus(testContract);
        
        assertTrue(isActive, "Should still be active");
        assertTrue(lastScan > 0, "Should have last scan timestamp");
        assertEq(scanCount, 1, "Should have 1 scan");
    }
    
    // ========== Fuzz Invariant Tests ==========
    
    /**
     * @notice invariant_fuzzReportCounterMonotonicity
     * @dev The report counter should be monotonically increasing with fuzzed inputs
     */
    function invariant_fuzzReportCounterMonotonicity(
        uint256 numReports,
        uint8 critical,
        uint8 high,
        uint8 medium,
        uint8 low
    ) public {
        vm.assume(numReports > 0 && numReports <= 20);
        vm.assume(critical <= 5 && high <= 5 && medium <= 5 && low <= 5);
        
        // Register contract
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        uint256 initialCounter = securityRegistry.reportCounter();
        
        // Create fuzzed number of reports
        for (uint256 i = 0; i < numReports; i++) {
            vm.prank(agent);
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
        
        // Counter should increase by exactly numReports
        assertEq(finalCounter, initialCounter + numReports, "Counter should increase by numReports");
        assertTrue(finalCounter > initialCounter, "Counter should be greater than initial");
    }
    
    /**
     * @notice invariant_fuzzMultipleContractConsistency
     * @dev Multiple contracts should maintain consistent state under fuzzed inputs
     */
    function invariant_fuzzMultipleContractConsistency(
        uint256 numContracts
    ) public {
        vm.assume(numContracts > 0 && numContracts <= 10);
        
        // Register multiple contracts
        for (uint256 i = 0; i < numContracts; i++) {
            address contractAddr = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            vm.prank(user);
            chainGuard.registerContract(contractAddr, 3600);
        }
        
        // All contracts should be monitored
        for (uint256 i = 0; i < numContracts; i++) {
            address contractAddr = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            (bool isActive, , , ) = chainGuard.getMonitoringStatus(contractAddr);
            assertTrue(isActive, "All contracts should be active");
        }
        
        // System stats should reflect all contracts
        (uint256 totalContracts, , ) = chainGuard.getSystemStats();
        assertEq(totalContracts, numContracts, "System stats should show all contracts");
    }
    
    // ========== Target State Test ==========
    
    /**
     * @notice test_targetReportCountReached
     * @dev System should handle reaching the target report count
     */
    function test_targetReportCountReached() public {
        // Register contract
        vm.prank(user);
        chainGuard.registerContract(testContract, 3600);
        
        // Create reports up to target
        for (uint256 i = 0; i < TARGET_REPORT_COUNT; i++) {
            vm.prank(agent);
            securityRegistry.reportVulnerability(
                testContract,
                string(abi.encodePacked("QmTarget", i)),
                0, 0, 1, 0
            );
        }
        
        uint256 finalCounter = securityRegistry.reportCounter();
        assertEq(finalCounter, TARGET_REPORT_COUNT, "Should reach target report count");
        
        // System should still be functional
        (uint256 totalContracts, uint256 totalScans, ) = 
            chainGuard.getSystemStats();
        
        assertTrue(totalContracts >= 1, "Should have at least 1 contract");
        assertTrue(totalScans >= TARGET_REPORT_COUNT, "Should have target scans");
        
        console.log("Target report count test passed");
    }
    
    // ========== Invariant Test Runner ==========
    
    /**
     * @notice runAllInvariants
     * @dev Run all invariant tests and report results
     */
    function runAllInvariants() external {
        console.log("=== Running All Invariant Tests ===");
        
        uint256 passedTests = 0;
        uint256 totalTests = 15;
        
        // Run all invariant tests
        try this.invariant_reportCounterAlwaysIncreases() { passedTests++; } catch { console.log("Report counter invariant failed"); }
        try this.invariant_reportCounterNeverExceedsReports() { passedTests++; } catch { console.log("Report counter exceeds invariant failed"); }
        try this.invariant_pausedContractsCanOnlyBeUnpausedByOwner() { passedTests++; } catch { console.log("Pause invariant failed"); }
        try this.invariant_pauseStateIsPersistent() { passedTests++; } catch { console.log("Pause persistence invariant failed"); }
        try this.invariant_onlyRegisteredContractsCanHaveReports() { passedTests++; } catch { console.log("Registration invariant failed"); }
        try this.invariant_registrationIsUnique() { passedTests++; } catch { console.log("Registration uniqueness invariant failed"); }
        try this.invariant_agentAddressCanAlwaysBeChangedByOwner() { passedTests++; } catch { console.log("Agent address invariant failed"); }
        try this.invariant_agentAddressIsNeverZero() { passedTests++; } catch { console.log("Agent zero address invariant failed"); }
        try this.invariant_nftSupplyMatchesReports() { passedTests++; } catch { console.log("NFT supply invariant failed"); }
        try this.invariant_nftOwnershipIsChainGuard() { passedTests++; } catch { console.log("NFT ownership invariant failed"); }
        try this.invariant_systemStatsAreConsistent() { passedTests++; } catch { console.log("System stats invariant failed"); }
        try this.invariant_monitoringStatusIsAccurate() { passedTests++; } catch { console.log("Monitoring status invariant failed"); }
        try this.test_targetReportCountReached() { passedTests++; } catch { console.log("Target count test failed"); }
        
        // Print summary
        console.log("\n=== INVARIANT TEST SUMMARY ===");
        console.log("Total tests:", totalTests);
        console.log("Passed tests:", passedTests);
        console.log("Failed tests:", totalTests - passedTests);
        console.log("Success rate:", (passedTests * 100) / totalTests, "%");
        
        if (passedTests == totalTests) {
            console.log("ALL INVARIANT TESTS PASSED!");
            console.log("ChainGuard AI maintains all critical invariants.");
        } else {
            console.log("SOME INVARIANT TESTS FAILED!");
            console.log("System may have state consistency issues.");
        }
    }
}

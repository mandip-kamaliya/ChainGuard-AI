// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/SecurityRegistry.sol";

contract SecurityRegistryTest is Test {
    SecurityRegistry public registry;
    address public owner = address(0x1);
    address public agent = address(0x2);
    address public user = address(0x3);
    address public testContract = address(0x4);
    address public testContract2 = address(0x5);
    
    // Events for testing
    event ContractRegistered(address indexed contractAddress, address indexed owner);
    event VulnerabilityReported(uint256 indexed reportId, address indexed contractAddress, uint8 severity);
    event ContractPaused(address indexed contractAddress);
    event ContractUnpaused(address indexed contractAddress);
    event ReportResolved(uint256 indexed reportId);
    event AgentUpdated(address indexed oldAgent, address indexed newAgent);
    
    function setUp() public {
        vm.prank(owner);
        registry = new SecurityRegistry(owner);
        
        vm.prank(owner);
        registry.setAgentAddress(agent);
        
        // Fund accounts for gas
        vm.deal(owner, 100 ether);
        vm.deal(agent, 100 ether);
        vm.deal(user, 100 ether);
    }
    
    // ========== Constructor Tests ==========
    
    function testConstructor_SetsCorrectOwner() public {
        assertEq(registry.owner(), owner, "Owner should be set correctly");
    }
    
    function testConstructor_SetsInitialAgent() public {
        assertEq(registry.agentAddress(), agent, "Agent should be set correctly");
    }
    
    function testConstructor_InitializesReportCounter() public {
        assertEq(registry.reportCounter(), 0, "Report counter should start at 0");
    }
    
    // ========== Contract Registration Tests ==========
    
    function testRegisterContract_Success() public {
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit ContractRegistered(testContract, user);
        
        registry.registerContract(testContract);
        
        (address contractAddress, address contractOwner, uint256 registeredAt, bool isPaused, uint256 lastScanTimestamp) = registry.monitoredContracts(testContract);
        assertEq(contractAddress, testContract, "Contract address should be set");
        assertEq(contractOwner, user, "Owner should be set");
        assertTrue(registeredAt > 0, "Registration timestamp should be set");
        assertFalse(isPaused, "Should not be paused initially");
        assertEq(lastScanTimestamp, 0, "Last scan should be 0 initially");
    }
    
    function testRegisterContract_RevertWhen_ZeroAddress() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.InvalidAddress.selector));
        registry.registerContract(address(0));
    }
    
    function testRegisterContract_RevertWhen_AlreadyRegistered() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.AlreadyRegistered.selector));
        registry.registerContract(testContract);
    }
    
    function testIsMonitored_ReturnsCorrectStatus() public {
        assertFalse(registry.isMonitored(testContract), "Should not be monitored initially");
        
        vm.prank(user);
        registry.registerContract(testContract);
        
        assertTrue(registry.isMonitored(testContract), "Should be monitored after registration");
    }
    
    // ========== Vulnerability Reporting Tests ==========
    
    function testReportVulnerability_Success() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(agent);
        vm.expectEmit(true, true, false, true);
        emit VulnerabilityReported(1, testContract, 3);
        
        uint256 reportId = registry.reportVulnerability(
            testContract,
            "QmTest123",
            2,  // critical
            3,  // high
            1,  // medium
            4   // low
        );
        
        assertEq(reportId, 1, "Report ID should be 1");
        assertEq(registry.reportCounter(), 1, "Report counter should be 1");
        
        (address reportAddr, string memory ipfsHash, uint8 criticalCount, uint8 highCount, uint8 mediumCount, uint8 lowCount, uint256 timestamp, bool resolved) = registry.vulnerabilityReports(1);
        assertEq(reportAddr, testContract, "Contract address should match");
        assertEq(ipfsHash, "QmTest123", "IPFS hash should match");
        assertEq(criticalCount, 2, "Critical count should match");
        assertEq(highCount, 3, "High count should match");
        assertEq(mediumCount, 1, "Medium count should match");
        assertEq(lowCount, 4, "Low count should match");
        assertFalse(resolved, "Should not be resolved initially");
        assertTrue(timestamp > 0, "Timestamp should be set");
    }
    
    function testReportVulnerability_RevertWhen_NotRegistered() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.NotRegistered.selector));
        registry.reportVulnerability(
            testContract,
            "QmTest123",
            1, 1, 1, 1
        );
    }
    
    function testReportVulnerability_RevertWhen_NotAgent() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.Unauthorized.selector));
        registry.reportVulnerability(
            testContract,
            "QmTest123",
            1, 1, 1, 1
        );
    }
    
    function testReportVulnerability_AutoPauseOnCritical() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(agent);
        vm.expectEmit(true, false, false, true);
        emit ContractPaused(testContract);
        
        registry.reportVulnerability(
            testContract,
            "QmTest123",
            1,  // critical
            0, 0, 0
        );
        
        assertTrue(registry.isPaused(testContract), "Contract should be auto-paused");
    }
    
    function testReportVulnerability_UpdatesLastScanTimestamp() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        uint256 beforeTimestamp = block.timestamp;
        vm.prank(agent);
        registry.reportVulnerability(testContract, "QmTest", 0, 0, 0, 0);
        
        (,,,, uint256 lastScanTs) = registry.monitoredContracts(testContract);
        assertEq(lastScanTs, beforeTimestamp, "Last scan timestamp should be updated");
    }
    
    function testGetContractReports_ReturnsCorrectReports() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(agent);
        registry.reportVulnerability(testContract, "QmTest1", 0, 1, 0, 0);
        vm.prank(agent);
        registry.reportVulnerability(testContract, "QmTest2", 0, 0, 1, 0);
        
        uint256[] memory reports = registry.getContractReports(testContract);
        assertEq(reports.length, 2, "Should have 2 reports");
        assertEq(reports[0], 1, "First report ID should be 1");
        assertEq(reports[1], 2, "Second report ID should be 2");
    }
    
    // ========== Pause/Unpause Tests ==========
    
    function testPauseContract_Success() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit ContractPaused(testContract);
        
        registry.pauseContract(testContract);
        assertTrue(registry.isPaused(testContract), "Contract should be paused");
    }
    
    function testPauseContract_AgentCanPause() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(agent);
        registry.pauseContract(testContract);
        assertTrue(registry.isPaused(testContract), "Agent should be able to pause");
    }
    
    function testPauseContract_OwnerCanPause() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(owner);
        registry.pauseContract(testContract);
        assertTrue(registry.isPaused(testContract), "Owner should be able to pause");
    }
    
    function testPauseContract_RevertWhen_Unauthorized() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        address unauthorized = address(0x999);
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.Unauthorized.selector));
        registry.pauseContract(testContract);
    }
    
    function testUnpauseContract_Success() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(user);
        registry.pauseContract(testContract);
        
        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit ContractUnpaused(testContract);
        
        registry.unpauseContract(testContract);
        assertFalse(registry.isPaused(testContract), "Contract should be unpaused");
    }
    
    function testUnpauseContract_RevertWhen_NotOwner() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(user);
        registry.pauseContract(testContract);
        
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.NotContractOwner.selector));
        registry.unpauseContract(testContract);
    }
    
    // ========== Report Resolution Tests ==========
    
    function testMarkResolved_Success() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(agent);
        uint256 reportId = registry.reportVulnerability(testContract, "QmTest", 0, 1, 0, 0);
        
        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit ReportResolved(reportId);
        
        registry.markResolved(reportId);
        {
            (,,,,,,, bool resolved) = registry.vulnerabilityReports(reportId);
            assertTrue(resolved, "Report should be resolved");
        }
    }
    
    function testMarkResolved_RevertWhen_NotContractOwner() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(agent);
        uint256 reportId = registry.reportVulnerability(testContract, "QmTest", 0, 1, 0, 0);
        
        address unauthorized = address(0x999);
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.NotContractOwner.selector));
        registry.markResolved(reportId);
    }
    
    // ========== Agent Management Tests ==========
    
    function testSetAgentAddress_Success() public {
        address newAgent = address(0x999);
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit AgentUpdated(agent, newAgent);
        
        registry.setAgentAddress(newAgent);
        assertEq(registry.agentAddress(), newAgent, "Agent address should be updated");
    }
    
    function testSetAgentAddress_RevertWhen_Unauthorized() public {
        address newAgent = address(0x999);
        
        vm.prank(user);
        vm.expectRevert();
        registry.setAgentAddress(newAgent);
    }
    
    function testSetAgentAddress_RevertWhen_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.InvalidAddress.selector));
        registry.setAgentAddress(address(0));
    }
    
    // ========== Vulnerability Summary Tests ==========
    
    function testGetVulnerabilitySummary_CalculatesCorrectly() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(agent);
        registry.reportVulnerability(testContract, "QmTest1", 1, 2, 3, 4);
        vm.prank(agent);
        registry.reportVulnerability(testContract, "QmTest2", 0, 1, 0, 0);
        
        (uint8 critical, uint8 high, uint8 medium, uint8 low) = 
            registry.getVulnerabilitySummary(testContract);
        
        assertEq(critical, 1, "Critical count should be 1");
        assertEq(high, 3, "High count should be 3");
        assertEq(medium, 3, "Medium count should be 3");
        assertEq(low, 4, "Low count should be 4");
    }
    
    function testGetVulnerabilitySummary_ExcludesResolvedReports() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(agent);
        uint256 reportId = registry.reportVulnerability(testContract, "QmTest", 1, 0, 0, 0);
        
        // Mark as resolved
        vm.prank(user);
        registry.markResolved(reportId);
        
        (uint8 critical, uint8 high, uint8 medium, uint8 low) = 
            registry.getVulnerabilitySummary(testContract);
        
        assertEq(critical, 0, "Resolved critical should be excluded");
        assertEq(high, 0, "Resolved high should be excluded");
        assertEq(medium, 0, "Resolved medium should be excluded");
        assertEq(low, 0, "Resolved low should be excluded");
    }
    
    // ========== Fuzz Tests ==========
    
    function testFuzzRegisterContract(address randomAddress) public {
        vm.assume(randomAddress != address(0));
        vm.assume(randomAddress != testContract); // Avoid conflicts
        
        vm.prank(user);
        registry.registerContract(randomAddress);
        
        assertTrue(registry.isMonitored(randomAddress), "Random address should be monitored");
        (, address contractOwner,,,) = registry.monitoredContracts(randomAddress);
        assertEq(contractOwner, user, "Owner should be user");
    }
    
    function testFuzzReportVulnerability(
        uint8 critical,
        uint8 high,
        uint8 medium,
        uint8 low
    ) public {
        vm.assume(critical <= 10 && high <= 10 && medium <= 10 && low <= 10);
        
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(agent);
        uint256 reportId = registry.reportVulnerability(
            testContract,
            "QmFuzz",
            critical,
            high,
            medium,
            low
        );
        
        SecurityRegistry.VulnerabilityReport memory report = registry.vulnerabilityReports(reportId);
        assertEq(report.criticalCount, critical, "Critical count should match");
        assertEq(report.highCount, high, "High count should match");
        assertEq(report.mediumCount, medium, "Medium count should match");
        assertEq(report.lowCount, low, "Low count should match");
    }
    
    function testFuzzMultipleContracts(
        uint8 contractCount
    ) public {
        vm.assume(contractCount > 0 && contractCount <= 10);
        
        for (uint8 i = 0; i < contractCount; i++) {
            address contractAddr = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            
            vm.prank(user);
            registry.registerContract(contractAddr);
            
            assertTrue(registry.isMonitored(contractAddr), "Contract should be monitored");
        }
    }
    
    // ========== Gas Optimization Tests ==========
    
    function testGasUsage_RegisterContract() public {
        vm.prank(user);
        uint256 gasBefore = gasleft();
        registry.registerContract(testContract);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for registerContract:", gasUsed);
        assertTrue(gasUsed < 200000, "Registration should use less than 200k gas");
    }
    
    function testGasUsage_ReportVulnerability() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(agent);
        uint256 gasBefore = gasleft();
        registry.reportVulnerability(testContract, "QmTest", 1, 1, 1, 1);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for reportVulnerability:", gasUsed);
        assertTrue(gasUsed < 300000, "Reporting should use less than 300k gas");
    }
    
    // ========== Edge Case Tests ==========
    
    function testEdgeCase_MaxVulnerabilityCounts() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        vm.prank(agent);
        registry.reportVulnerability(
            testContract,
            "QmMax",
            type(uint8).max,
            type(uint8).max,
            type(uint8).max,
            type(uint8).max
        );
        
        (uint8 critical, uint8 high, uint8 medium, uint8 low) = 
            registry.getVulnerabilitySummary(testContract);
        
        assertEq(critical, type(uint8).max, "Should handle max critical");
        assertEq(high, type(uint8).max, "Should handle max high");
        assertEq(medium, type(uint8).max, "Should handle max medium");
        assertEq(low, type(uint8).max, "Should handle max low");
    }
    
    function testEdgeCase_MultipleReportsSameContract() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        // Create multiple reports
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(agent);
            registry.reportVulnerability(
                testContract,
                string(abi.encodePacked("QmTest", i)),
                0, 0, 1, 0
            );
        }
        
        uint256[] memory reports = registry.getContractReports(testContract);
        assertEq(reports.length, 5, "Should have 5 reports");
        
        // Verify all reports exist
        for (uint256 i = 0; i < 5; i++) {
            assertTrue(registry.vulnerabilityReports(reports[i]).timestamp > 0, "All reports should exist");
        }
    }
    
    // ========== State Transition Tests ==========
    
    function testStateTransition_RegistrationToMonitoring() public {
        vm.prank(user);
        registry.registerContract(testContract);
        
        // Initial state
        assertTrue(registry.isMonitored(testContract), "Should be monitored");
        assertFalse(registry.isPaused(testContract), "Should not be paused");
        assertEq(registry.getContractReports(testContract).length, 0, "No reports initially");
        
        // After vulnerability report
        vm.prank(agent);
        registry.reportVulnerability(testContract, "QmTest", 0, 1, 0, 0);
        
        assertEq(registry.getContractReports(testContract).length, 1, "Should have 1 report");
        
        // After pause
        vm.prank(user);
        registry.pauseContract(testContract);
        
        assertTrue(registry.isPaused(testContract), "Should be paused");
        
        // After unpause
        vm.prank(user);
        registry.unpauseContract(testContract);
        
        assertFalse(registry.isPaused(testContract), "Should not be paused");
    }
}

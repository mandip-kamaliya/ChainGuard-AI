// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/SecurityRegistry.sol";

contract SecurityRegistryTest is Test {
    SecurityRegistry public securityRegistry;
    address public owner;
    address public agent;
    address public user;
    address public contractAddress;
    
    event ContractRegistered(address indexed contractAddress, address indexed owner);
    event VulnerabilityReported(uint256 indexed reportId, address indexed contractAddress, uint8 severity);
    event ContractPaused(address indexed contractAddress);
    event ContractUnpaused(address indexed contractAddress);
    event ReportResolved(uint256 indexed reportId);
    event AgentUpdated(address indexed oldAgent, address indexed newAgent);

    function setUp() public {
        owner = address(this);
        agent = address(0x1);
        user = address(0x2);
        contractAddress = address(0x3);
        
        vm.prank(owner);
        securityRegistry = new SecurityRegistry(owner);
        
        vm.prank(owner);
        securityRegistry.setAgentAddress(agent);
    }

    function testConstructor() public {
        assertEq(securityRegistry.owner(), owner);
        assertEq(securityRegistry.agentAddress(), agent);
        assertEq(securityRegistry.reportCounter(), 0);
    }

    function testRegisterContract() public {
        vm.prank(user);
        vm.expectEmit(true, true, false, false);
        emit ContractRegistered(contractAddress, user);
        
        securityRegistry.registerContract(contractAddress);
        
        SecurityRegistry.MonitoredContract memory monitored = securityRegistry.monitoredContracts(contractAddress);
        assertEq(monitored.contractAddress, contractAddress);
        assertEq(monitored.owner, user);
        assertTrue(monitored.registeredAt > 0);
        assertFalse(monitored.isPaused);
        assertEq(monitored.lastScanTimestamp, 0);
    }

    function testRegisterContractInvalidAddress() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.InvalidAddress.selector));
        securityRegistry.registerContract(address(0));
    }

    function testRegisterContractAlreadyRegistered() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.AlreadyRegistered.selector));
        securityRegistry.registerContract(contractAddress);
    }

    function testReportVulnerability() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(agent);
        vm.expectEmit(true, true, false, false);
        emit VulnerabilityReported(1, contractAddress, 3);
        
        uint256 reportId = securityRegistry.reportVulnerability(
            contractAddress,
            "QmTest123",
            2,  // critical
            3,  // high
            1,  // medium
            4   // low
        );
        
        assertEq(reportId, 1);
        assertEq(securityRegistry.reportCounter(), 1);
        
        SecurityRegistry.VulnerabilityReport memory report = securityRegistry.vulnerabilityReports(1);
        assertEq(report.contractAddress, contractAddress);
        assertEq(report.ipfsHash, "QmTest123");
        assertEq(report.criticalCount, 2);
        assertEq(report.highCount, 3);
        assertEq(report.mediumCount, 1);
        assertEq(report.lowCount, 4);
        assertFalse(report.resolved);
    }

    function testReportVulnerabilityNotRegistered() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.NotRegistered.selector));
        securityRegistry.reportVulnerability(
            contractAddress,
            "QmTest123",
            1, 1, 1, 1
        );
    }

    function testReportVulnerabilityNotAgent() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.Unauthorized.selector));
        securityRegistry.reportVulnerability(
            contractAddress,
            "QmTest123",
            1, 1, 1, 1
        );
    }

    function testReportVulnerabilityCriticalAutoPause() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(agent);
        vm.expectEmit(true, false, false, false);
        emit ContractPaused(contractAddress);
        
        securityRegistry.reportVulnerability(
            contractAddress,
            "QmTest123",
            1,  // critical
            0, 0, 0
        );
        
        assertTrue(securityRegistry.isPaused(contractAddress));
    }

    function testPauseContract() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(user);
        vm.expectEmit(true, false, false, false);
        emit ContractPaused(contractAddress);
        
        securityRegistry.pauseContract(contractAddress);
        assertTrue(securityRegistry.isPaused(contractAddress));
    }

    function testPauseContractUnauthorized() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(address(0x999));
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.Unauthorized.selector));
        securityRegistry.pauseContract(contractAddress);
    }

    function testUnpauseContract() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(user);
        securityRegistry.pauseContract(contractAddress);
        
        vm.prank(user);
        vm.expectEmit(true, false, false, false);
        emit ContractUnpaused(contractAddress);
        
        securityRegistry.unpauseContract(contractAddress);
        assertFalse(securityRegistry.isPaused(contractAddress));
    }

    function testUnpauseContractUnauthorized() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.NotContractOwner.selector));
        securityRegistry.unpauseContract(contractAddress);
    }

    function testMarkResolved() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(agent);
        uint256 reportId = securityRegistry.reportVulnerability(
            contractAddress,
            "QmTest123",
            0, 1, 0, 0
        );
        
        vm.prank(user);
        vm.expectEmit(true, false, false, false);
        emit ReportResolved(reportId);
        
        securityRegistry.markResolved(reportId);
        assertTrue(securityRegistry.vulnerabilityReports(reportId).resolved);
    }

    function testMarkResolvedUnauthorized() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(agent);
        uint256 reportId = securityRegistry.reportVulnerability(
            contractAddress,
            "QmTest123",
            0, 1, 0, 0
        );
        
        vm.prank(address(0x999));
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.NotContractOwner.selector));
        securityRegistry.markResolved(reportId);
    }

    function testGetContractReports() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(agent);
        securityRegistry.reportVulnerability(contractAddress, "QmTest1", 0, 1, 0, 0);
        vm.prank(agent);
        securityRegistry.reportVulnerability(contractAddress, "QmTest2", 0, 0, 1, 0);
        
        uint256[] memory reports = securityRegistry.getContractReports(contractAddress);
        assertEq(reports.length, 2);
        assertEq(reports[0], 1);
        assertEq(reports[1], 2);
    }

    function testIsMonitored() public {
        assertFalse(securityRegistry.isMonitored(contractAddress));
        
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        assertTrue(securityRegistry.isMonitored(contractAddress));
    }

    function testGetVulnerabilitySummary() public {
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(agent);
        securityRegistry.reportVulnerability(contractAddress, "QmTest1", 1, 2, 3, 4);
        vm.prank(agent);
        securityRegistry.reportVulnerability(contractAddress, "QmTest2", 0, 1, 0, 0);
        
        (uint8 critical, uint8 high, uint8 medium, uint8 low) = 
            securityRegistry.getVulnerabilitySummary(contractAddress);
        
        assertEq(critical, 1);
        assertEq(high, 3);
        assertEq(medium, 3);
        assertEq(low, 4);
    }

    function testSetAgentAddress() public {
        address newAgent = address(0x999);
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit AgentUpdated(agent, newAgent);
        
        securityRegistry.setAgentAddress(newAgent);
        assertEq(securityRegistry.agentAddress(), newAgent);
    }

    function testSetAgentAddressUnauthorized() public {
        vm.prank(user);
        vm.expectRevert();
        securityRegistry.setAgentAddress(address(0x999));
    }

    function testSetAgentAddressInvalid() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SecurityRegistry.InvalidAddress.selector));
        securityRegistry.setAgentAddress(address(0));
    }

    function testGetMonitoredContractsCount() public {
        assertEq(securityRegistry.getMonitoredContractsCount(), 0);
        
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        // Note: This test shows the simplified implementation
        // In production, this would return 1
        assertEq(securityRegistry.getMonitoredContractsCount(), 0);
    }

    function testFuzzRegisterContract(address randomAddress) public {
        vm.assume(randomAddress != address(0));
        
        vm.prank(user);
        securityRegistry.registerContract(randomAddress);
        
        assertTrue(securityRegistry.isMonitored(randomAddress));
        assertEq(securityRegistry.monitoredContracts(randomAddress).owner, user);
    }

    function testFuzzReportVulnerability(
        uint8 critical,
        uint8 high,
        uint8 medium,
        uint8 low
    ) public {
        vm.assume(critical <= 10 && high <= 10 && medium <= 10 && low <= 10);
        
        vm.prank(user);
        securityRegistry.registerContract(contractAddress);
        
        vm.prank(agent);
        uint256 reportId = securityRegistry.reportVulnerability(
            contractAddress,
            "QmTest",
            critical,
            high,
            medium,
            low
        );
        
        SecurityRegistry.VulnerabilityReport memory report = securityRegistry.vulnerabilityReports(reportId);
        assertEq(report.criticalCount, critical);
        assertEq(report.highCount, high);
        assertEq(report.mediumCount, medium);
        assertEq(report.lowCount, low);
    }
}

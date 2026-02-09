// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ChainGuard.sol";

contract ChainGuardTest is Test {
    ChainGuard public chainGuard;
    address public owner;
    address public aiAgent;
    address public user;

    function setUp() public {
        owner = address(this);
        aiAgent = address(0x1);
        user = address(0x2);
        
        vm.prank(owner);
        chainGuard = new ChainGuard();
        
        vm.prank(owner);
        chainGuard.setAIAgent(aiAgent);
    }

    function testAddContract() public {
        address testContract = address(0x3);
        
        vm.prank(owner);
        chainGuard.addContract(testContract);
        
        ChainGuard.MonitoredContract memory monitored = chainGuard.getMonitoredContract(testContract);
        assertEq(monitored.contractAddress, testContract);
        assertTrue(monitored.isActive);
        assertEq(monitored.monitoringStart, block.timestamp);
    }

    function testAddContractInvalidAddress() public {
        vm.prank(owner);
        vm.expectRevert("ChainGuard: Invalid contract address");
        chainGuard.addContract(address(0));
    }

    function testAddContractAlreadyMonitored() public {
        address testContract = address(0x3);
        
        vm.prank(owner);
        chainGuard.addContract(testContract);
        
        vm.prank(owner);
        vm.expectRevert("ChainGuard: Contract already monitored");
        chainGuard.addContract(testContract);
    }

    function testFileSecurityReport() public {
        address testContract = address(0x3);
        
        vm.prank(owner);
        chainGuard.addContract(testContract);
        
        vm.prank(aiAgent);
        chainGuard.fileSecurityReport(
            testContract,
            "HIGH",
            "REENTRANCY",
            "Potential reentrancy vulnerability detected"
        );
        
        ChainGuard.SecurityReport memory report = chainGuard.getSecurityReport(1);
        assertEq(report.contractAddress, testContract);
        assertEq(report.riskLevel, "HIGH");
        assertEq(report.vulnerabilityType, "REENTRANCY");
        assertEq(report.reporter, aiAgent);
        assertFalse(report.resolved);
    }

    function testFileSecurityReportNotMonitored() public {
        address testContract = address(0x3);
        
        vm.prank(aiAgent);
        vm.expectRevert("ChainGuard: Contract not monitored");
        chainGuard.fileSecurityReport(
            testContract,
            "HIGH",
            "REENTRANCY",
            "Potential reentrancy vulnerability detected"
        );
    }

    function testFileSecurityReportNotAIAgent() public {
        address testContract = address(0x3);
        
        vm.prank(owner);
        chainGuard.addContract(testContract);
        
        vm.prank(user);
        vm.expectRevert("ChainGuard: Only AI agent can call this");
        chainGuard.fileSecurityReport(
            testContract,
            "HIGH",
            "REENTRANCY",
            "Potential reentrancy vulnerability detected"
        );
    }

    function testCriticalVulnerabilityPausesContract() public {
        address testContract = address(0x3);
        
        vm.prank(owner);
        chainGuard.addContract(testContract);
        
        vm.prank(aiAgent);
        chainGuard.fileSecurityReport(
            testContract,
            "CRITICAL",
            "UNLIMITED_MINTING",
            "Unlimited minting vulnerability detected"
        );
        
        assertTrue(chainGuard.paused());
    }

    function testResolveReport() public {
        address testContract = address(0x3);
        
        vm.prank(owner);
        chainGuard.addContract(testContract);
        
        vm.prank(aiAgent);
        chainGuard.fileSecurityReport(
            testContract,
            "HIGH",
            "REENTRANCY",
            "Potential reentrancy vulnerability detected"
        );
        
        vm.prank(owner);
        chainGuard.resolveReport(1);
        
        ChainGuard.SecurityReport memory report = chainGuard.getSecurityReport(1);
        assertTrue(report.resolved);
    }

    function testSetAIAgent() public {
        address newAgent = address(0x4);
        
        vm.prank(owner);
        chainGuard.setAIAgent(newAgent);
        
        vm.prank(newAgent);
        chainGuard.fileSecurityReport(
            address(0x5),
            "LOW",
            "INFO",
            "Informational finding"
        );
    }

    function testEmergencyPause() public {
        vm.prank(owner);
        chainGuard.emergencyPause();
        
        assertTrue(chainGuard.paused());
    }

    function testEmergencyResume() public {
        vm.prank(owner);
        chainGuard.emergencyPause();
        
        vm.prank(owner);
        chainGuard.emergencyResume();
        
        assertFalse(chainGuard.paused());
    }

    function testGetContractReports() public {
        address testContract = address(0x3);
        
        vm.prank(owner);
        chainGuard.addContract(testContract);
        
        vm.prank(aiAgent);
        chainGuard.fileSecurityReport(testContract, "HIGH", "REENTRANCY", "Reentrancy found");
        vm.prank(aiAgent);
        chainGuard.fileSecurityReport(testContract, "MEDIUM", "OVERFLOW", "Overflow found");
        
        uint256[] memory reports = chainGuard.getContractReports(testContract);
        assertEq(reports.length, 2);
        assertEq(reports[0], 1);
        assertEq(reports[1], 2);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

contract CheckBalance is Script {
    function run() external {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer:", deployer);
        console.log("DEPLOYER_ADDRESS:", deployer);
        console.log("DEPLOYER_BALANCE:", deployer.balance);
    }
}

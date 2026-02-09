// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/ChainGuard.sol";

contract DeployScript is Script {
    ChainGuard public chainGuard;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        chainGuard = new ChainGuard();
        
        vm.stopBroadcast();
        
        console.log("ChainGuard deployed at:", address(chainGuard));
        console.log("Deployer:", deployer);
        console.log("Transaction hash:", vm.getTransactionHash());
    }
}

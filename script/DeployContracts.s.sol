// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { Script, console } from "forge-std/Script.sol";
import { KillSwitch } from "../src/KillSwitch.sol";
import { UniversalGaslessDelegate } from "../src/UniversalGaslessDelegate.sol";

contract UGaslessDelegateDeploy is Script {
    KillSwitch public killSwitch;
    address killSwitchOwner = vm.envAddress(string.concat("KILL_SWITCH_OWNER_", vm.toString(block.chainid)));

    function setUp() public { }

    function run() public {
        vm.startBroadcast();

        killSwitch = new KillSwitch(killSwitchOwner);
        console.log("KillSwitch deployed to:", address(killSwitch));
        UniversalGaslessDelegate delegate = new UniversalGaslessDelegate(address(killSwitch));
        console.log("UniversalGaslessDelegate deployed to:", address(delegate));

        vm.stopBroadcast();
    }
}

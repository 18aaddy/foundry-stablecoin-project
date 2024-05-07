//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract DeployDsc is Script {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine) {
        vm.startBroadcast();
        dsc = new DecentralizedStableCoin();
        dscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
        vm.stopBroadcast();
        return (dsc, dscEngine);
    }
}

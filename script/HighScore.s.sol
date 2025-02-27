// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {HighScores} from "../src/HighScores/HighScores.sol";

contract HighScoresScript is Script {
    HighScores public highScore;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        address serverSigner = 0x8579F6A5a355280Dc1bc1219b5d5CAEA2319663B;
        highScore = new HighScores(serverSigner);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {TicTacToe} from "../src/TicTacToe/TicTacToe.sol";

contract TicTacScript is Script {
    TicTacToe public ticTacToe;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ticTacToe = new TicTacToe();

        vm.stopBroadcast();
    }
}

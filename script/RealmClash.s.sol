// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {CharacterCard} from "../src/RealmClash/ClashBattle/CharacterCard.sol";
import {RealmClashBattleSystem} from "../src/RealmClash/ClashBattle/Clash.sol";

contract RealmCLashScript is Script {
    CharacterCard public charactercard;
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        charactercard = new CharacterCard();
        vm.stopBroadcast();
    }
}

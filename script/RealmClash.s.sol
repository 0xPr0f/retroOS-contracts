// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {CharacterCard} from "../src/RealmClash/ClashBattle/CharacterCard.sol";
import {RealmClashBattleSystem} from "../src/RealmClash/ClashBattle/Clash.sol";

contract RealmCLashScript is Script {
    CharacterCard public charactercard;
    RealmClashBattleSystem public battleSystem;
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        //  charactercard = new CharacterCard();
        charactercard = CharacterCard(
            0x89b0f7569115BbF5fB4451E05bD1854b253763b6
        );
        battleSystem = new RealmClashBattleSystem(address(charactercard));
        charactercard.changeMinterStatus(address(battleSystem));
        vm.stopBroadcast();
    }
}

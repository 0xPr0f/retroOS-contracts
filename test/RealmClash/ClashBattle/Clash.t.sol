// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {RealmClashBattleSystem} from "../../../src/RealmClash/ClashBattle/Clash.sol";
import {CharacterCard} from "../../../src/RealmClash/ClashBattle/CharacterCard.sol";

contract RealmClashBattleSystemTest is Test {
    RealmClashBattleSystem battleSystem;
    CharacterCard characterContract;

    address player1 = address(1);
    address player2 = address(2);
    uint256 character1Id;
    uint256 character2Id;

    function setUp() public {
        characterContract = new CharacterCard();
        battleSystem = new RealmClashBattleSystem(address(characterContract));
        characterContract.changeMinterStatus(address(battleSystem));
        vm.prank(player1);
        characterContract.createCharacter(
            "Player1 Mage", //name
            "uri", //token uri
            50, //strength
            50, //defence
            50, //agility
            50, //vitality
            50, //intelligence
            50, //mp
            2 //Mage
        );
        character1Id = 1;

        vm.prank(player2);
        characterContract.createCharacter(
            "Player2 Knight", //name
            "uri", //token uri
            50, //strength
            50, //defence
            50, //agility
            50, //vitality
            50, //intelligence
            50, //mp
            4 //Knight
        );
        character2Id = 2;
    }

    function test_JoinAndLeaveMatchmaking() public {
        vm.startPrank(player1);
        battleSystem.joinMatchmaking(character1Id);
        vm.stopPrank();

        (address[] memory players, uint256[] memory characterIds) = battleSystem
            .getWaitingPlayers();
        assertEq(players.length, 1);
        assertEq(players[0], player1);
        assertEq(characterIds[0], character1Id);

        vm.startPrank(player1);
        battleSystem.leaveMatchmaking();
        vm.stopPrank();

        (players, characterIds) = battleSystem.getWaitingPlayers();
        assertEq(players.length, 0);
    }

    function test_CreateBattleThroughMatchmaking() public {
        vm.startPrank(player1);
        battleSystem.joinMatchmaking(character1Id);
        vm.stopPrank();

        vm.startPrank(player2);
        battleSystem.joinMatchmaking(character2Id);
        vm.stopPrank();

        uint256 battleId = battleSystem.getActiveBattle(player1);
        assertGt(battleId, 0);
        assertEq(battleId, battleSystem.getActiveBattle(player2));
    }

    function test_ChallengePlayer() public {
        vm.startPrank(player1);
        battleSystem.challengePlayer(player2, character1Id);
        vm.stopPrank();

        uint256 pendingChallenge = battleSystem.getPendingChallenge(
            player1,
            player2
        );
        assertEq(pendingChallenge, character1Id);
    }

    function test_AcceptChallenge() public {
        vm.startPrank(player1);
        battleSystem.challengePlayer(player2, character1Id);
        vm.stopPrank();

        vm.startPrank(player2);
        battleSystem.acceptChallenge(player1, character2Id);
        vm.stopPrank();

        uint256 battleId = battleSystem.getActiveBattle(player1);
        assertGt(battleId, 0);
        assertEq(battleId, battleSystem.getActiveBattle(player2));

        uint256 pendingChallenge = battleSystem.getPendingChallenge(
            player1,
            player2
        );
        assertEq(pendingChallenge, 0);
    }

    function test_RejectChallenge() public {
        vm.startPrank(player1);
        battleSystem.challengePlayer(player2, character1Id);
        vm.stopPrank();

        vm.startPrank(player2);
        battleSystem.rejectChallenge(player1);
        vm.stopPrank();

        uint256 pendingChallenge = battleSystem.getPendingChallenge(
            player1,
            player2
        );
        assertEq(pendingChallenge, 0);
    }

    function test_PerformAttack() public {
        uint256 battleId = _createTestBattle();

        vm.startPrank(player1);
        battleSystem.performAttack(battleId, 1);
        vm.stopPrank();

        (, , , , , uint256 totalDamageDealt) = battleSystem.getBattleProgress(
            battleId
        );
        assertGt(totalDamageDealt, 0);
    }
    function test_EndTurnAndStartNewRound() public {
        uint256 battleId = _createTestBattle();

        (address initialPlayer, , ) = battleSystem.getCurrentTurnInfo(battleId);

        vm.startPrank(initialPlayer);
        battleSystem.endTurn(battleId);
        vm.stopPrank();

        (address currentPlayer, uint8 points, bool turnEnded) = battleSystem
            .getCurrentTurnInfo(battleId);

        assertEq(
            currentPlayer,
            player2 /*Player 1 is a mage and naturally have more intelligence so it was the first to play*/,
            "Turn should switch to player 2"
        );
        assertTrue(
            !turnEnded,
            "New player's turn should not be marked as ended"
        );

        vm.startPrank(currentPlayer);
        battleSystem.endTurn(battleId);
        vm.stopPrank();

        (currentPlayer, points, turnEnded) = battleSystem.getCurrentTurnInfo(
            battleId
        );
        assertTrue(points > 0, "New round should generate new attack points");
        assertTrue(!turnEnded, "New round should reset turn ended status");
    }

    function test_ForfeitBattle() public {
        uint256 battleId = _createTestBattle();

        vm.startPrank(player2);
        battleSystem.forfeitBattle(battleId);
        vm.stopPrank();

        (, , , , , , address winner, , , ) = battleSystem.getBattleDetails(
            battleId
        );
        assertEq(winner, player1);
    }

    function test_CheckBattleTimeout() public {
        uint256 battleId = _createTestBattle();

        vm.warp(block.timestamp + battleSystem.BATTLE_TIMEOUT() + 1);
        battleSystem.checkBattleTimeout(battleId);

        (
            ,
            ,
            ,
            ,
            RealmClashBattleSystem.BattleState state,
            ,
            ,
            ,
            ,

        ) = battleSystem.getBattleDetails(battleId);
        assertEq(
            uint256(state),
            uint256(RealmClashBattleSystem.BattleState.Canceled)
        );
    }

    function test_CheckTurnTimeout() public {
        uint256 battleId = _createTestBattle();

        vm.warp(block.timestamp + battleSystem.TURN_TIMEOUT() + 1);
        battleSystem.checkTurnTimeout(battleId);

        (, , , , , , address winner, , , ) = battleSystem.getBattleDetails(
            battleId
        );
        assertEq(winner, player2);
    }

    function test_EmergencyCancelBattle() public {
        uint256 battleId = _createTestBattle();

        battleSystem.emergencyCancelBattle(battleId);

        (
            ,
            ,
            ,
            ,
            RealmClashBattleSystem.BattleState state,
            ,
            ,
            ,
            ,

        ) = battleSystem.getBattleDetails(battleId);
        assertEq(
            uint256(state),
            uint256(RealmClashBattleSystem.BattleState.Canceled)
        );
    }

    function test_SetCharacterContract() public {
        CharacterCard newCharacterContract = new CharacterCard();
        battleSystem.setCharacterContract(address(newCharacterContract));

        assertEq(
            address(battleSystem.characterContract()),
            address(newCharacterContract)
        );
    }

    function test_UpdateBattleTimeout() public {
        uint256 newTimeout = 2 days;
        battleSystem.updateBattleTimeout(newTimeout);

        assertEq(battleSystem.BATTLE_TIMEOUT(), newTimeout);
    }

    function test_UpdateTurnTimeout() public {
        uint256 newTimeout = 15 minutes;
        battleSystem.updateTurnTimeout(newTimeout);

        assertEq(battleSystem.TURN_TIMEOUT(), newTimeout);
    }

    function test_PlayFullGame() public {
        uint256 battleId = _createTestBattle();

        (
            uint256 player1Damage,
            bool player1IsCrit,
            uint256 player1CritDamage
        ) = characterContract.calculateDamage(character1Id);
        (
            uint256 player2Damage,
            bool player2IsCrit,
            uint256 player2CritDamage
        ) = characterContract.calculateDamage(character2Id);
        uint256 player1Health = characterContract.calculateHealth(character1Id);
        uint256 player2Health = characterContract.calculateHealth(character2Id);
        uint256 player1Defense = characterContract.calculateDefense(
            character1Id
        );
        uint256 player2Defense = characterContract.calculateDefense(
            character2Id
        );
        uint256 player1MagicPower = characterContract.getEffectiveMagicPower(
            character1Id
        );
        uint256 player2MagicPower = characterContract.getEffectiveMagicPower(
            character2Id
        );

        console.log("Player 1 (Mage)");
        console.log("  Damage: %s, IsCrit: %s", player1Damage, player1IsCrit);
        console.log(
            "  CritDamage: %s, Health: %s",
            player1CritDamage,
            player1Health
        );
        console.log(
            "  Defense: %s, MagicPower: %s",
            player1Defense,
            player1MagicPower
        );

        console.log("Player 2 (Knight)");
        console.log("  Damage: %s, IsCrit: %s", player2Damage, player2IsCrit);
        console.log(
            "  CritDamage: %s, Health: %s",
            player2CritDamage,
            player2Health
        );
        console.log(
            "  Defense: %s, MagicPower: %s",
            player2Defense,
            player2MagicPower
        );

        for (uint256 round = 1; round <= 4; round++) {
            console.log("Round %s", round);

            (address player1Address, uint8 player1AttackPoints, ) = battleSystem
                .getCurrentTurnInfo(battleId);
            console.log("  Player 1's turn");
            console.log("    Attack Points: %s", player1AttackPoints);
            _performAttack(player1Address, battleId, 2);

            (address player2Address, uint8 player2AttackPoints, ) = battleSystem
                .getCurrentTurnInfo(battleId);
            console.log("  Player 2's turn");
            console.log("    Attack Points: %s", player2AttackPoints);
            _performAttack(player2Address, battleId, 1);
        }

        (
            uint256 player1CurrentHealth,
            uint256 player1MaxHealth,
            uint256 player2CurrentHealth,
            uint256 player2MaxHealth,
            uint256 turnsCompleted,
            uint256 totalDamageDealt
        ) = battleSystem.getBattleProgress(battleId);

        (, , , , , , address winner, , , ) = battleSystem.getBattleDetails(
            battleId
        );

        console.log("Battle Results:");
        console.log(
            "  Winner: %s",
            winner != address(0)
                ? (winner == player1 ? "Player 1" : "Player 2")
                : "Not finished"
        );
        console.log("  Player 1 - CurrentHealth: %s", player1CurrentHealth);
        console.log("             MaxHealth: %s", player1MaxHealth);
        console.log("  Player 2 - CurrentHealth: %s", player2CurrentHealth);
        console.log("             MaxHealth: %s", player2MaxHealth);
        console.log("  Turns Completed: %s", turnsCompleted);
        console.log("  Total Damage Dealt: %s", totalDamageDealt);
    }
    function _performAttack(
        address player,
        uint256 battleId,
        uint8 _attackType /*1,2,3*/
    )
        internal
        returns (
            address currentPlayer,
            uint8 currentAttackPoints,
            bool turnEnded
        )
    {
        vm.startPrank(player);
        battleSystem.performAttack(battleId, _attackType);
        vm.stopPrank();
        (address initialPlayer, uint8 initialPoints, ) = battleSystem
            .getCurrentTurnInfo(battleId);
        return (initialPlayer, initialPoints, false);
    }

    function _createTestBattle() internal returns (uint256) {
        vm.startPrank(player1);
        battleSystem.challengePlayer(player2, character1Id);
        vm.stopPrank();

        vm.startPrank(player2);
        battleSystem.acceptChallenge(player1, character2Id);
        vm.stopPrank();

        return battleSystem.getActiveBattle(player1);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../../src/RealmClash/RNGBattle/RandomOutcomeClash.sol";

contract MockVRFCoordinator is Test {
    function requestRandomness(bytes32, uint256) public view returns (bytes32) {
        uint256 initialSlotValue = uint256(vm.load(address(msg.sender), bytes32(uint256(7))));
        bytes32 requestId = bytes32(uint256(vm.load(address(msg.sender), bytes32(uint256(7)))));
        if (uint256(requestId) == initialSlotValue) {
            requestId = keccak256(abi.encodePacked(blockhash(block.number - 1), address(msg.sender), uint256(1)));
        }
        return requestId;
    }

    function callBackWithRandomness(bytes32 requestId, uint256 randomness, address consumerContract) external {
        VRFConsumerBase(consumerContract).rawFulfillRandomness(requestId, randomness);
    }
}

contract MockLinkToken {
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transferAndCall(address to, uint256 value, bytes calldata) external returns (bool) {
        _balances[msg.sender] -= value;
        _balances[to] += value;
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _balances[msg.sender] -= value;
        _balances[to] += value;
        return true;
    }
}

contract RealmClashRNGCombatTest is Test {
    RealmClashRNGCombat public game;
    MockVRFCoordinator public vrfCoordinator;
    MockLinkToken public linkToken;

    address public owner = address(1);
    address public alice = address(2);
    address public bob = address(3);

    bytes32 keyHash = keccak256("keyHash");
    uint256 fee = 0.1 ether;

    event WarriorCreated(uint256 indexed id, address indexed owner, string name);
    event BattleInitiated(uint256 indexed battleId, uint256 indexed challengerId, uint256 indexed defenderId);
    event BattleCompleted(uint256 indexed battleId, uint256 indexed winner, uint256 indexed loser);
    event VeteranStatusAchieved(uint256 indexed warriorId);

    function setUp() public {
        vrfCoordinator = new MockVRFCoordinator();
        linkToken = new MockLinkToken();

        vm.startPrank(owner);
        game = new RealmClashRNGCombat(address(vrfCoordinator), address(linkToken), keyHash, fee);
        vm.stopPrank();

        linkToken.mint(address(game), 100 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function _createBalancedWarrior(address player, string memory name) internal returns (uint256) {
        vm.startPrank(player);
        vm.expectEmit(true, true, false, true);
        emit WarriorCreated(game._tokenIdsCounter() + 1, player, name);
        uint256 createdWarriorId = game.createWarrior(name, 40, 40, 40, 40, 40);
        vm.stopPrank();
        return createdWarriorId;
    }

    function _createCustomWarrior(
        address player,
        string memory name,
        uint8 strength,
        uint8 defense,
        uint8 agility,
        uint8 vitality,
        uint8 intelligence
    ) internal returns (uint256) {
        vm.startPrank(player);
        uint256 warriorId = game.createWarrior(name, strength, defense, agility, vitality, intelligence);
        vm.stopPrank();
        return warriorId;
    }

    function testWarriorCreation() public {
        string memory name = "Aragorn";
        uint8 strength = 50;
        uint8 defense = 40;
        uint8 agility = 40;
        uint8 vitality = 30;
        uint8 intelligence = 40;

        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true);
        emit WarriorCreated(1, alice, name);
        game.createWarrior(name, strength, defense, agility, vitality, intelligence);
        vm.stopPrank();

        (
            uint256 id,
            string memory storedName,
            uint8 storedStrength,
            uint8 storedDefense,
            uint8 storedAgility,
            uint8 storedVitality,
            uint8 storedIntelligence,
            uint16 wins,
            uint16 losses,
            bool isVeteran,
            uint256 lastBattleTime
        ) = game.warriors(1);

        assertEq(id, 1, "Warrior ID should be 1");
        assertEq(storedName, name, "Name should match");
        assertEq(storedStrength, strength, "Strength should match");
        assertEq(storedDefense, defense, "Defense should match");
        assertEq(storedAgility, agility, "Agility should match");
        assertEq(storedVitality, vitality, "Vitality should match");
        assertEq(storedIntelligence, intelligence, "Intelligence should match");
        assertEq(wins, 0, "Wins should be 0");
        assertEq(losses, 0, "Losses should be 0");
        assertEq(isVeteran, false, "Veteran status should be false");
        assertEq(lastBattleTime, 0, "Last battle time should be 0");
        assertEq(game.ownerOf(1), alice, "Alice should own the warrior");
    }

    function test_Revert_CreateWarriorInvalidStats() public {
        vm.startPrank(alice);
        vm.expectRevert();
        game.createWarrior("Failed Warrior", 0, 50, 50, 50, 50);
        vm.stopPrank();
    }

    function test_Revert_CreateWarriorExceedingStats() public {
        vm.startPrank(alice);
        vm.expectRevert();

        game.createWarrior("Failed Warrior", 101, 50, 50, 50, 50);
        vm.stopPrank();
    }

    function test__Revert_CreateWarriorIncorrectTotal() public {
        vm.startPrank(alice);
        vm.expectRevert();

        game.createWarrior("Failed Warrior", 30, 30, 30, 30, 30);
        vm.stopPrank();
    }

    function test_InitiateBattle() public {
        uint256 aliceWarriorId = _createBalancedWarrior(alice, "Alice's Warrior");
        uint256 bobWarriorId = _createBalancedWarrior(bob, "Bob's Warrior");

        vm.startPrank(alice);
        game.initiateBattle(aliceWarriorId, bobWarriorId);
        vm.stopPrank();

        (uint256 id, uint256 challenger, uint256 defender, uint256 winner, uint256 timestamp, bool completed) =
            game.battles(1);

        assertEq(id, 1, "Battle ID should be 1");
        assertEq(challenger, aliceWarriorId, "Challenger should be Alice's warrior");
        assertEq(defender, bobWarriorId, "Defender should be Bob's warrior");
        assertEq(winner, 0, "Winner should be 0 (not determined yet)");
        assertEq(timestamp, block.timestamp, "Timestamp should be current block timestamp");
        assertEq(completed, false, "Battle should not be completed yet");
    }

    function test_Revert_BattleOwnWarrior() public {
        uint256 warrior1 = _createBalancedWarrior(alice, "Warrior 1");
        uint256 warrior2 = _createCustomWarrior(alice, "Warrior 2", 50, 40, 30, 40, 40);

        vm.startPrank(alice);
        vm.expectRevert();
        game.initiateBattle(warrior1, warrior2);
        vm.stopPrank();
    }

    function test_Revert_BattleNotOwner() public {
        uint256 aliceWarriorId = _createBalancedWarrior(alice, "Alice's Warrior");
        uint256 bobWarriorId = _createBalancedWarrior(bob, "Bob's Warrior");

        vm.startPrank(bob);
        vm.expectRevert();
        game.initiateBattle(aliceWarriorId, bobWarriorId);
        vm.stopPrank();
    }

    /* function test_BattleResolution() public {
        uint256 aliceWarriorId = _createCustomWarrior(alice, "High Strength", 80, 30, 30, 30, 30);
        uint256 bobWarriorId = _createCustomWarrior(bob, "High Defense", 30, 80, 30, 30, 30);

        vm.startPrank(alice);
        console.log(aliceWarriorId, bobWarriorId);
        bytes32 requestId = _initiateBattleAndCaptureRequestId(aliceWarriorId, bobWarriorId);
        vm.stopPrank();

        uint256 randomNumber = 12345;
        vm.startPrank(address(vrfCoordinator));
        vrfCoordinator.callBackWithRandomness(requestId, randomNumber, address(game));
        vm.stopPrank();

        (uint256 id, uint256 challenger, uint256 defender, uint256 winner,, bool completed) = game.battles(1);

        assertEq(id, 1, "Battle ID should be 1");
        assertEq(challenger, aliceWarriorId, "Challenger should be Alice's warrior");
        assertEq(defender, bobWarriorId, "Defender should be Bob's warrior");
        assertTrue(winner == aliceWarriorId || winner == bobWarriorId, "Winner should be one of the warriors");
        assertTrue(completed, "Battle should be completed");

        (,,,,,,, uint16 aliceWins, uint16 aliceLosses,,) = game.warriors(aliceWarriorId);
        (,,,,,,, uint16 bobWins, uint16 bobLosses,,) = game.warriors(bobWarriorId);

        if (winner == aliceWarriorId) {
            assertEq(aliceWins, 1, "Alice should have 1 win");
            assertEq(bobLosses, 1, "Bob should have 1 loss");
            assertEq(bobWins, 0, "Bob should have 0 wins");
            assertEq(aliceLosses, 0, "Alice should have 0 losses");
        } else {
            assertEq(bobWins, 1, "Bob should have 1 win");
            assertEq(aliceLosses, 1, "Alice should have 1 loss");
            assertEq(aliceWins, 0, "Alice should have 0 wins");
            assertEq(bobLosses, 0, "Bob should have 0 losses");
        }
    }

    function test_VeteranStatus() public {
        uint256 aliceWarriorId = _createCustomWarrior(alice, "Glass Cannon", 100, 1, 49, 25, 25);
        uint256 bobWarriorId = _createCustomWarrior(bob, "Tank", 1, 100, 49, 25, 25);

        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + game.BATTLE_COOLDOWN() + 1);

            vm.startPrank(alice);
            bytes32 requestId = _initiateBattleAndCaptureRequestId(aliceWarriorId, bobWarriorId);
            vm.stopPrank();

            uint256 randomNumber = 500000 + i;

            if (i == 9) {
                vm.expectEmit(true, false, false, false);
                emit VeteranStatusAchieved(aliceWarriorId);
            }

            vm.prank(address(vrfCoordinator));
            vrfCoordinator.callBackWithRandomness(requestId, randomNumber, address(game));
        }

        (,,,,,,, uint16 wins,, bool isVeteran,) = game.warriors(aliceWarriorId);
        assertEq(wins, 10, "Alice's warrior should have 10 wins");
        assertTrue(isVeteran, "Alice's warrior should now be a veteran");
    }
    */
    function test_BattleCooldown() public {
        uint256 aliceWarriorId = _createBalancedWarrior(alice, "Alice's Warrior");
        uint256 bobWarriorId = _createBalancedWarrior(bob, "Bob's Warrior");

        vm.startPrank(alice);
        game.initiateBattle(aliceWarriorId, bobWarriorId);
        vm.expectRevert("Challenger on cooldown");
        game.initiateBattle(aliceWarriorId, bobWarriorId);
        vm.stopPrank();

        vm.warp(block.timestamp + game.BATTLE_COOLDOWN() + 1);

        vm.startPrank(alice);
        game.initiateBattle(aliceWarriorId, bobWarriorId);
        vm.stopPrank();

        assertTrue(true);
    }

    function test_GetWarriorsByOwner() public {
        _createCustomWarrior(alice, "Warrior 1", 40, 40, 40, 40, 40);
        _createCustomWarrior(alice, "Warrior 2", 50, 50, 50, 25, 25);
        _createCustomWarrior(alice, "Warrior 3", 60, 60, 30, 30, 20);
        _createBalancedWarrior(bob, "Bob's Warrior");

        uint256[] memory aliceWarriors = game.getWarriorsByOwner(alice);
        uint256[] memory bobWarriors = game.getWarriorsByOwner(bob);

        assertEq(aliceWarriors.length, 3, "Alice should have 3 warriors");
        assertEq(bobWarriors.length, 1, "Bob should have 1 warrior");

        assertEq(aliceWarriors[0], 1, "First warrior ID should be 1");
        assertEq(aliceWarriors[1], 2, "Second warrior ID should be 2");
        assertEq(aliceWarriors[2], 3, "Third warrior ID should be 3");
        assertEq(bobWarriors[0], 4, "Bob's warrior ID should be 4");
    }

    function test_Withdraw() public {
        vm.deal(address(game), 5 ether);

        uint256 ownerBalanceBefore = owner.balance;
        vm.prank(owner);
        game.withdraw();
        uint256 ownerBalanceAfter = owner.balance;

        assertEq(address(game).balance, 0, "Contract should have 0 balance after withdrawal");
        assertEq(ownerBalanceAfter - ownerBalanceBefore, 5 ether, "Owner should receive 5 ether");
    }

    function test_WithdrawLink() public {
        linkToken.mint(address(game), 10 ether);

        uint256 ownerLinkBefore = linkToken.balanceOf(owner);
        vm.prank(owner);
        game.withdrawLink(5 ether);
        uint256 ownerLinkAfter = linkToken.balanceOf(owner);

        assertEq(ownerLinkAfter - ownerLinkBefore, 5 ether, "Owner should receive 5 LINK tokens");
    }

    function test_Revert_WithdrawNotOwner() public {
        vm.deal(address(game), 1 ether);
        vm.prank(alice);
        vm.expectRevert();

        game.withdraw();
    }

    function test_GetWarrior() public {
        string memory name = "Test Warrior";
        _createBalancedWarrior(alice, name);

        RealmClashRNGCombat.Warrior memory warrior = game.getWarrior(1);
        assertEq(warrior.name, name, "Name should match");
        assertEq(warrior.strength, 40, "Strength should be 40");
        assertEq(warrior.wins, 0, "Wins should be 0");
    }

    function test_GetBattle() public {
        uint256 aliceWarriorId = _createBalancedWarrior(alice, "Alice Warrior");
        uint256 bobWarriorId = _createBalancedWarrior(bob, "Bob Warrior");

        vm.prank(alice);
        game.initiateBattle(aliceWarriorId, bobWarriorId);

        RealmClashRNGCombat.Battle memory battle = game.getBattle(1);
        assertEq(battle.challenger, aliceWarriorId, "Challenger ID should match");
        assertEq(battle.defender, bobWarriorId, "Defender ID should match");
        assertEq(battle.completed, false, "Battle should not be completed");
    }

    function test_Revert_GetNonExistentWarrior() public {
        vm.expectRevert();
        game.getWarrior(999);
    }

    function test_Revert_GetNonExistentBattle() public {
        vm.expectRevert();
        game.getBattle(999);
    }

    function _initiateBattleAndCaptureRequestId(uint256 challengerId, uint256 defenderId) internal returns (bytes32) {
        uint256 initialSlotValue = uint256(vm.load(address(game), bytes32(uint256(7))));
        game.initiateBattle(challengerId, defenderId);
        bytes32 requestId = bytes32(uint256(vm.load(address(game), bytes32(uint256(7)))));
        if (uint256(requestId) == initialSlotValue) {
            requestId = keccak256(abi.encodePacked(blockhash(block.number - 1), address(game), uint256(1)));
        }
        return requestId;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/HighScores/HighScores.sol";

contract HighScoresTest is Test {
    HighScores public highScores;
    address public serverKey;
    address public owner;
    address public player1;
    address public player2;
    uint256 public serverPrivateKey;

    event ScoreSubmitted(
        address player,
        HighScores.GameType gameType,
        uint256 score
    );
    event ServerPublicKeyUpdated(address newKey);

    function setUp() public {
        // Generate server key pair
        serverPrivateKey = 0x1234;
        serverKey = vm.addr(serverPrivateKey);

        // Setup contract
        owner = address(this);
        highScores = new HighScores(serverKey);

        // Setup test accounts
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");

        // Fund test accounts
        vm.deal(player1, 100 ether);
        vm.deal(player2, 100 ether);
    }

    function testInitialState() public view {
        assertEq(highScores.serverPublicKey(), serverKey);
        assertEq(highScores.owner(), owner);
        assertEq(highScores.getTotalPlayers(HighScores.GameType.SNAKE), 0);
        assertEq(highScores.getTotalPlayers(HighScores.GameType.TETRIS), 0);
    }

    function testSubmitScore() public {
        uint256 score = 100;
        HighScores.GameType gameType = HighScores.GameType.SNAKE;

        // Create signature with player1 address
        bytes32 messageHash = keccak256(
            abi.encodePacked(player1, score, gameType)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            serverPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Submit score as player1
        vm.prank(player1);
        vm.expectEmit(true, true, true, true);
        emit ScoreSubmitted(player1, gameType, score);
        highScores.submitScore(player1, score, gameType, signature);

        // Verify score was recorded
        assertEq(highScores.getHighestScore(player1, gameType), score);
        assertEq(highScores.getTotalPlayers(gameType), 1);
    }

    function testSubmitMultipleScores() public {
        HighScores.GameType gameType = HighScores.GameType.SNAKE;
        uint256[] memory scores = new uint256[](3);
        scores[0] = 100;
        scores[1] = 200;
        scores[2] = 150;

        for (uint256 i = 0; i < scores.length; i++) {
            // Create signature
            bytes32 messageHash = keccak256(
                abi.encodePacked(player1, scores[i], gameType)
            );
            bytes32 ethSignedMessageHash = keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    messageHash
                )
            );
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                serverPrivateKey,
                ethSignedMessageHash
            );
            bytes memory signature = abi.encodePacked(r, s, v);

            // Submit score
            vm.prank(player1);
            highScores.submitScore(player1, scores[i], gameType, signature);
        }

        // Verify highest score
        assertEq(highScores.getHighestScore(player1, gameType), 200);

        // Verify all scores
        HighScores.Score[] memory allScores = highScores.getAllScores(
            player1,
            gameType
        );
        assertEq(allScores.length, 3);
        assertEq(allScores[0].score, 100);
        assertEq(allScores[1].score, 200);
        assertEq(allScores[2].score, 150);
    }

    function testLeaderboard() public {
        HighScores.GameType gameType = HighScores.GameType.SNAKE;

        // Submit scores for player1 and player2
        submitScoreForPlayer(player1, 100, gameType);
        submitScoreForPlayer(player2, 200, gameType);

        // Get leaderboard
        HighScores.LeaderboardEntry[] memory leaderboard = highScores
            .getLeaderboard(gameType, 2);

        // Verify leaderboard order
        assertEq(leaderboard.length, 2);
        assertEq(leaderboard[0].player, player2);
        assertEq(leaderboard[0].highScore, 200);
        assertEq(leaderboard[1].player, player1);
        assertEq(leaderboard[1].highScore, 100);
    }

    function testLatestScores() public {
        HighScores.GameType gameType = HighScores.GameType.SNAKE;

        // Submit multiple scores for player1
        submitScoreForPlayer(player1, 100, gameType);
        submitScoreForPlayer(player1, 200, gameType);
        submitScoreForPlayer(player1, 150, gameType);

        // Get latest 2 scores
        HighScores.Score[] memory latestScores = highScores.getLatestScores(
            player1,
            gameType,
            2
        );

        // Verify latest scores
        assertEq(latestScores.length, 2);
        assertEq(latestScores[0].score, 200);
        assertEq(latestScores[1].score, 150);
    }

    function testUpdateServerPublicKey() public {
        address newServerKey = makeAddr("newServer");

        vm.expectEmit(true, true, true, true);
        emit ServerPublicKeyUpdated(newServerKey);
        highScores.updateServerPublicKey(newServerKey);

        assertEq(highScores.serverPublicKey(), newServerKey);
    }

    function test_RevertSubmitScoreInvalidSignature() public {
        uint256 score = 100;
        HighScores.GameType gameType = HighScores.GameType.SNAKE;

        // Create signature with wrong private key
        uint256 wrongPrivateKey = 0x5678;
        bytes32 messageHash = keccak256(
            abi.encodePacked(player1, score, gameType)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            wrongPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(player1);
        vm.expectRevert();
        highScores.submitScore(player1, score, gameType, signature);
    }

    function test_RevertSubmitScoreWrongPlayer() public {
        uint256 score = 100;
        HighScores.GameType gameType = HighScores.GameType.SNAKE;

        // Create signature with player1 address
        bytes32 messageHash = keccak256(
            abi.encodePacked(player1, score, gameType)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            serverPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Try to submit score as player2 with player1's signature
        vm.prank(player2);
        vm.expectRevert();
        highScores.submitScore(player1, score, gameType, signature);
    }

    function test_RevertSubmitScoreWithWrongAddress() public {
        uint256 score = 100;
        HighScores.GameType gameType = HighScores.GameType.SNAKE;

        // Create signature with player1 address
        bytes32 messageHash = keccak256(
            abi.encodePacked(player1, score, gameType)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            serverPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Try to submit score as player1 but with player2's address in the parameters
        vm.prank(player1);
        vm.expectRevert();
        highScores.submitScore(player2, score, gameType, signature);
    }

    function test_RevertUpdateServerKeyNonOwner() public {
        address newServerKey = makeAddr("newServer");

        vm.prank(player1);
        vm.expectRevert();
        highScores.updateServerPublicKey(newServerKey);
    }

    // Helper function for tests that submit multiple scores
    function submitScoreForPlayer(
        address player,
        uint256 score,
        HighScores.GameType gameType
    ) internal {
        bytes32 messageHash = keccak256(
            abi.encodePacked(player, score, gameType)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            serverPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(player);
        highScores.submitScore(player, score, gameType, signature);
    }
}

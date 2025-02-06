// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TicTacToe} from "../../src/TicTacToe/TicTacToe.sol";

contract TicTacToeTest is Test {
    event GameReset(bytes32 gameId);
    event GameDrawn(bytes32 gameId);

    TicTacToe public game;
    address public player1;
    address public player2;

    function setUp() public {
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        game = new TicTacToe();
    }

    /*
    Final board state after test:
    
     X | X | X
    ---+---+---
     O | O |  
    ---+---+---
     |   |  
    
    Where:
    X = 1 (Player 1's moves)
    O = 2 (Player 2's moves)
    Empty = 0
    */
    function testFullGame() public {
        // Player 1 joins queue
        vm.prank(player1);
        game.joinQueue();

        // Player 2 joins queue and they get matched
        vm.prank(player2);
        game.joinQueue();

        // Get the game ID for player1
        bytes32 gameId = game.getCurrentGame(player1);

        // Verify both players are in the same game
        assertEq(game.getCurrentGame(player2), gameId);

        // Get initial game state
        (
            address playerX,
            address playerO,
            address winner,
            bool isActive,
            uint8[9] memory board,
            bool isXNext
        ) = game.getGameState(gameId);

        // Verify initial state
        assertEq(playerX, player1);
        assertEq(playerO, player2);
        assertEq(winner, address(0));
        assertTrue(isActive);
        assertTrue(isXNext);

        // Player X (player1) makes first move
        vm.prank(player1);
        game.makeMove(gameId, 0); // top left [X, _, _, _, _, _, _, _, _]

        // Player O (player2) makes move
        vm.prank(player2);
        game.makeMove(gameId, 4); // center [X, _, _, _, O, _, _, _, _]

        // Player X makes move
        vm.prank(player1);
        game.makeMove(gameId, 1); // top middle [X, X, _, _, O, _, _, _, _]

        // Player O makes move
        vm.prank(player2);
        game.makeMove(gameId, 3); // middle left [X, X, _, O, O, _, _, _, _]

        // Player X makes winning move
        vm.prank(player1);
        game.makeMove(gameId, 2); // top right [X, X, X, O, O, _, _, _, _]

        // Verify final state
        (playerX, playerO, winner, isActive, board, isXNext) = game
            .getGameState(gameId);

        assertEq(winner, player1);
        assertFalse(isActive);

        // Verify board state
        assertEq(board[0], 1); // X - top left
        assertEq(board[1], 1); // X - top middle
        assertEq(board[2], 1); // X - top right
        assertEq(board[3], 2); // O - middle left
        assertEq(board[4], 2); // O - center
    }

    function testFailInvalidMove() public {
        // Player 1 joins queue
        vm.prank(player1);
        game.joinQueue();

        // Player 2 joins queue
        vm.prank(player2);
        game.joinQueue();

        bytes32 gameId = game.getCurrentGame(player1);

        // Player O tries to move first (should fail)
        vm.prank(player2);
        game.makeMove(gameId, 0);
    }

    function testFailMoveOnFinishedGame() public {
        // Player 1 joins queue
        vm.prank(player1);
        game.joinQueue();

        // Player 2 joins queue
        vm.prank(player2);
        game.joinQueue();

        bytes32 gameId = game.getCurrentGame(player1);

        // Play winning game for X
        vm.prank(player1);
        game.makeMove(gameId, 0); // [X, _, _, _, _, _, _, _, _]
        vm.prank(player2);
        game.makeMove(gameId, 3); // [X, _, _, O, _, _, _, _, _]
        vm.prank(player1);
        game.makeMove(gameId, 1); // [X, X, _, O, _, _, _, _, _]
        vm.prank(player2);
        game.makeMove(gameId, 4); // [X, X, _, O, O, _, _, _, _]
        vm.prank(player1);
        game.makeMove(gameId, 2); // [X, X, X, O, O, _, _, _, _]

        // Try to make move after game is won (should fail)
        vm.prank(player2);
        game.makeMove(gameId, 5);
    }

    function testDrawAndReset() public {
        // Player 1 joins queue
        vm.prank(player1);
        game.joinQueue();

        // Player 2 joins queue
        vm.prank(player2);
        game.joinQueue();

        bytes32 gameId = game.getCurrentGame(player1);

        // Play to a draw
        vm.prank(player1);
        game.makeMove(gameId, 0); // [X, _, _, _, _, _, _, _, _]
        vm.prank(player2);
        game.makeMove(gameId, 1); // [X, O, _, _, _, _, _, _, _]
        vm.prank(player1);
        game.makeMove(gameId, 2); // [X, O, X, _, _, _, _, _, _]
        vm.prank(player2);
        game.makeMove(gameId, 4); // [X, O, X, _, X, _, _, _, _]
        vm.prank(player1);
        game.makeMove(gameId, 7); // [X, O, X, _, O, _, _, O, _]
        vm.prank(player2);
        game.makeMove(gameId, 5); // [X, O, X, _, O, 0, _, X, _]
        vm.prank(player1);
        game.makeMove(gameId, 3); // [X, O, X, X, O, 0, _, X, _]
        vm.prank(player2);
        game.makeMove(gameId, 6); // [X, O, X, O, O, X, O, X, _]

        vm.expectEmit(false, false, false, false);
        emit GameDrawn(gameId);
        emit GameReset(gameId);

        vm.prank(player1);
        game.makeMove(gameId, 8); // [X, O, X, O, O, X, O, X, X]
        /*0X 1O 2X
          3O 4X 50
          6O 7O 8X
*/

        // Get game state after draw
        (, , , bool isActive, uint8[9] memory board, ) = game.getGameState(
            gameId
        );

        // Game should still be active after draw and reset
        assertTrue(isActive);

        // Board should be reset to empty
        for (uint i = 0; i < 9; i++) {
            assertEq(board[i], 0);
        }

        vm.prank(player2);
        game.makeMove(gameId, 8);
    }

    function testFailMoveToOccupiedPosition() public {
        // Player 1 joins queue
        vm.prank(player1);
        game.joinQueue();

        // Player 2 joins queue
        vm.prank(player2);
        game.joinQueue();

        bytes32 gameId = game.getCurrentGame(player1);

        // Player 1 makes first move
        vm.prank(player1);
        game.makeMove(gameId, 0); // [X, _, _, _, _, _, _, _, _]

        // Player 2 tries to move to same position
        vm.prank(player2);
        game.makeMove(gameId, 0); // Should fail
    }
}

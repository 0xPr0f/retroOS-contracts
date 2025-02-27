// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract TicTacToe {
    struct Game {
        address playerX;
        address playerO;
        address winner;
        bool isActive;
        uint8[9] board;
        bool isXNext;
        uint256 lastMoveTime;
    }

    struct Player {
        address playerAddress;
        uint256 joinedAt;
        bool isMatched;
    }

    mapping(bytes32 => Game) public games;
    mapping(address => bool) public isInQueue;
    mapping(address => bytes32) public playerToGame;

    Player[] public playerQueue;
    uint256 public constant TIMEOUT_DURATION = 5 minutes;

    event GameCreated(bytes32 gameId, address playerX);
    event PlayerJoined(bytes32 gameId, address playerO);
    event MoveMade(bytes32 gameId, uint8 position, address player);
    event GameWon(bytes32 gameId, address winner);
    event GameDrawn(bytes32 gameId);
    event GameReset(bytes32 gameId);
    event PlayerJoinedQueue(address player, uint256 position);
    event PlayersMatched(address player1, address player2, bytes32 gameId);
    event PlayerLeftQueue(address player);
    event PlayerLeftGame(bytes32 gameId, address player, address winner);

    function joinQueue() external {
        require(!isInQueue[msg.sender], "Already in queue");
        require(playerToGame[msg.sender] == bytes32(0), "Already in a game");

        // If queue is empty, just add player
        if (playerQueue.length == 0) {
            playerQueue.push(Player({playerAddress: msg.sender, joinedAt: block.timestamp, isMatched: false}));
            isInQueue[msg.sender] = true;
            emit PlayerJoinedQueue(msg.sender, 0);
            return;
        }

        // Get first unmatched player in queue
        Player storage opponent = playerQueue[0];
        require(!opponent.isMatched, "First player already matched");

        // Create game with first player in queue
        bytes32 gameId = createGame(opponent.playerAddress);
        joinGame(gameId, msg.sender);

        // Update player statuses
        opponent.isMatched = true;
        playerToGame[opponent.playerAddress] = gameId;
        playerToGame[msg.sender] = gameId;

        emit PlayersMatched(opponent.playerAddress, msg.sender, gameId);

        // Remove matched player from queue
        if (playerQueue.length > 1) {
            playerQueue[0] = playerQueue[playerQueue.length - 1];
        }
        playerQueue.pop();
    }

    function leaveQueue() external {
        require(isInQueue[msg.sender], "Not in queue");
        require(playerToGame[msg.sender] == bytes32(0), "Already in a game");

        for (uint256 i = 0; i < playerQueue.length; i++) {
            if (playerQueue[i].playerAddress == msg.sender) {
                if (i != playerQueue.length - 1) {
                    playerQueue[i] = playerQueue[playerQueue.length - 1];
                }
                playerQueue.pop();
                isInQueue[msg.sender] = false;
                emit PlayerLeftQueue(msg.sender);
                break;
            }
        }
    }

    function leaveGame() external {
        bytes32 gameId = playerToGame[msg.sender];
        require(gameId != bytes32(0), "Not in a game");

        Game storage game = games[gameId];
        require(game.isActive, "Game is not active");
        require(msg.sender == game.playerX || msg.sender == game.playerO, "Not a player in this game");

        // Set the other player as winner
        address winner = msg.sender == game.playerX ? game.playerO : game.playerX;
        game.winner = winner;
        game.isActive = false;

        // Reset player states
        playerToGame[game.playerX] = bytes32(0);
        playerToGame[game.playerO] = bytes32(0);
        isInQueue[game.playerX] = false;
        isInQueue[game.playerO] = false;

        emit PlayerLeftGame(gameId, msg.sender, winner);
        emit GameWon(gameId, winner);
    }

    function cleanupMatchedPlayers() internal {
        uint256 i = 0;
        while (i < playerQueue.length) {
            if (playerQueue[i].isMatched) {
                if (i != playerQueue.length - 1) {
                    playerQueue[i] = playerQueue[playerQueue.length - 1];
                    i--;
                }
                playerQueue.pop();
            }
            i++;
        }
    }

    function createGame(address player) internal returns (bytes32) {
        bytes32 gameId = keccak256(abi.encodePacked(block.timestamp, player));
        require(games[gameId].playerX == address(0), "Game ID already exists");

        games[gameId] = Game({
            playerX: player,
            playerO: address(0),
            winner: address(0),
            isActive: true,
            board: [0, 0, 0, 0, 0, 0, 0, 0, 0],
            isXNext: true,
            lastMoveTime: block.timestamp
        });

        emit GameCreated(gameId, player);
        return gameId;
    }

    function joinGame(bytes32 gameId, address player) internal {
        Game storage game = games[gameId];
        require(game.playerX != address(0), "Game does not exist");
        require(game.playerO == address(0), "Game is full");
        require(game.playerX != player, "Cannot play against yourself");

        game.playerO = player;
        emit PlayerJoined(gameId, player);
    }

    function makeMove(bytes32 gameId, uint8 position) external {
        Game storage game = games[gameId];
        require(game.isActive, "Game is not active");
        require(position < 9, "Invalid position");
        require(game.board[position] == 0, "Position already taken");

        if (game.isXNext) {
            require(msg.sender == game.playerX, "Not player X's turn");
        } else {
            require(msg.sender == game.playerO, "Not player O's turn");
        }

        game.board[position] = game.isXNext ? 1 : 2;
        game.isXNext = !game.isXNext;
        game.lastMoveTime = block.timestamp;

        emit MoveMade(gameId, position, msg.sender);

        if (checkWinner(game.board)) {
            game.winner = msg.sender;
            game.isActive = false;
            // Remove players from game and queue when there's a winner
            playerToGame[game.playerX] = bytes32(0);
            playerToGame[game.playerO] = bytes32(0);
            isInQueue[game.playerX] = false;
            isInQueue[game.playerO] = false;
            emit GameWon(gameId, msg.sender);
        } else if (isDraw(game.board)) {
            // Reset the board and continue playing
            game.board = [0, 0, 0, 0, 0, 0, 0, 0, 0];
            emit GameDrawn(gameId);
            emit GameReset(gameId);
        }
    }

    function checkWinner(uint8[9] memory board) internal pure returns (bool) {
        uint8[3][8] memory lines = [
            [0, 1, 2],
            [3, 4, 5],
            [6, 7, 8], // rows
            [0, 3, 6],
            [1, 4, 7],
            [2, 5, 8], // columns
            [0, 4, 8],
            [2, 4, 6] // diagonals
        ];

        for (uint256 i = 0; i < lines.length; i++) {
            if (
                board[lines[i][0]] != 0 && board[lines[i][0]] == board[lines[i][1]]
                    && board[lines[i][0]] == board[lines[i][2]]
            ) {
                return true;
            }
        }
        return false;
    }

    function isDraw(uint8[9] memory board) internal pure returns (bool) {
        for (uint256 i = 0; i < 9; i++) {
            if (board[i] == 0) {
                return false;
            }
        }
        return true;
    }

    function getGameState(bytes32 gameId)
        external
        view
        returns (address playerX, address playerO, address winner, bool isActive, uint8[9] memory board, bool isXNext)
    {
        Game storage game = games[gameId];
        return (game.playerX, game.playerO, game.winner, game.isActive, game.board, game.isXNext);
    }

    function getQueueLength() external view returns (uint256) {
        return playerQueue.length;
    }

    function getPlayerQueuePosition(address player) external view returns (uint256) {
        for (uint256 i = 0; i < playerQueue.length; i++) {
            if (playerQueue[i].playerAddress == player) {
                return i + 1;
            }
        }
        return 0;
    }

    function getCurrentGame(address player) external view returns (bytes32) {
        return playerToGame[player];
    }
}

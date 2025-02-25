// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract HighScores {
    address public serverPublicKey;
    address public owner;

    enum GameType {
        SNAKE,
        TETRIS
    }

    struct Score {
        address player;
        uint256 score;
        uint256 timestamp;
        bytes signature;
    }

    struct LeaderboardEntry {
        address player;
        uint256 highScore;
        uint256 lastPlayed;
    }

    // Mapping: player address => game type => array of scores
    mapping(address => mapping(GameType => Score[])) private playerScores;

    // Keep track of unique players for each game type
    mapping(GameType => address[]) private gamePlayers;
    mapping(GameType => mapping(address => bool)) private isPlayerRegistered;

    event ScoreSubmitted(address player, GameType gameType, uint256 score);
    event ServerPublicKeyUpdated(address newKey);

    constructor(address _serverPublicKey) {
        serverPublicKey = _serverPublicKey;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    function submitScore(
        address player,
        uint256 score,
        GameType gameType,
        bytes memory signature
    ) public {
        require(player == msg.sender, "Player address must match sender");

        bytes32 messageHash = keccak256(
            abi.encodePacked(player, score, gameType)
        );

        address signer = recoverSigner(messageHash, signature);

        require(signer == serverPublicKey, "Invalid signature");

        if (!isPlayerRegistered[gameType][player]) {
            gamePlayers[gameType].push(player);
            isPlayerRegistered[gameType][player] = true;
        }

        Score memory newScore = Score({
            player: player,
            score: score,
            timestamp: block.timestamp,
            signature: signature
        });

        playerScores[player][gameType].push(newScore);

        emit ScoreSubmitted(player, gameType, score);
    }

    function batchSubmitScores(
        address player,
        uint256[] memory scores,
        GameType[] memory gameTypes,
        bytes[] memory signatures
    ) public {
        require(
            scores.length == gameTypes.length &&
                scores.length == signatures.length,
            "Input arrays must have the same length"
        );
        require(player == msg.sender, "Player address must match sender");

        for (uint256 i = 0; i < scores.length; i++) {
            bytes32 messageHash = keccak256(
                abi.encodePacked(player, scores[i], gameTypes[i])
            );
            address signer = recoverSigner(messageHash, signatures[i]);
            require(signer == serverPublicKey, "Invalid signature");

            if (!isPlayerRegistered[gameTypes[i]][player]) {
                gamePlayers[gameTypes[i]].push(player);
                isPlayerRegistered[gameTypes[i]][player] = true;
            }
            Score memory newScore = Score({
                player: player,
                score: scores[i],
                timestamp: block.timestamp,
                signature: signatures[i]
            });

            playerScores[player][gameTypes[i]].push(newScore);
            emit ScoreSubmitted(player, gameTypes[i], scores[i]);
        }
    }

    function getHighestScore(
        address player,
        GameType gameType
    ) public view returns (uint256) {
        Score[] storage scores = playerScores[player][gameType];

        if (scores.length == 0) {
            return 0;
        }

        uint256 highestScore = 0;
        for (uint256 i = 0; i < scores.length; i++) {
            if (scores[i].score > highestScore) {
                highestScore = scores[i].score;
            }
        }

        return highestScore;
    }

    function getLeaderboard(
        GameType gameType,
        uint256 limit
    ) public view returns (LeaderboardEntry[] memory) {
        address[] storage players = gamePlayers[gameType];

        // Determine the number of entries to return
        uint256 numEntries = limit < players.length ? limit : players.length;
        LeaderboardEntry[] memory leaderboard = new LeaderboardEntry[](
            numEntries
        );

        // First, populate the leaderboard array
        for (uint256 i = 0; i < numEntries; i++) {
            address player = players[i];
            Score[] storage playerScoreArray = playerScores[player][gameType];

            uint256 highestScore = 0;
            uint256 lastPlayed = 0;

            for (uint256 j = 0; j < playerScoreArray.length; j++) {
                if (playerScoreArray[j].score > highestScore) {
                    highestScore = playerScoreArray[j].score;
                }
                if (playerScoreArray[j].timestamp > lastPlayed) {
                    lastPlayed = playerScoreArray[j].timestamp;
                }
            }

            leaderboard[i] = LeaderboardEntry({
                player: player,
                highScore: highestScore,
                lastPlayed: lastPlayed
            });
        }

        // Sort the leaderboard by score (bubble sort)
        for (uint256 i = 0; i < numEntries - 1; i++) {
            for (uint256 j = 0; j < numEntries - i - 1; j++) {
                if (leaderboard[j].highScore < leaderboard[j + 1].highScore) {
                    LeaderboardEntry memory temp = leaderboard[j];
                    leaderboard[j] = leaderboard[j + 1];
                    leaderboard[j + 1] = temp;
                }
            }
        }

        return leaderboard;
    }

    function getAllScores(
        address player,
        GameType gameType
    ) public view returns (Score[] memory) {
        return playerScores[player][gameType];
    }

    function getLatestScores(
        address player,
        GameType gameType,
        uint256 count
    ) public view returns (Score[] memory) {
        Score[] storage allScores = playerScores[player][gameType];
        uint256 resultCount = count > allScores.length
            ? allScores.length
            : count;

        Score[] memory latestScores = new Score[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            latestScores[i] = allScores[allScores.length - resultCount + i];
        }

        return latestScores;
    }

    function getTotalPlayers(GameType gameType) public view returns (uint256) {
        return gamePlayers[gameType].length;
    }

    function updateServerPublicKey(address newKey) public onlyOwner {
        serverPublicKey = newKey;
        emit ServerPublicKeyUpdated(newKey);
    }

    // Helper function to recover signer from signature
    function recoverSigner(
        bytes32 messageHash,
        bytes memory signature
    ) internal pure returns (address) {
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = splitSignature(signature);

        return ecrecover(ethSignedMessageHash, v, r, s);
    }

    // Helper function to split signature into v, r, s components
    function splitSignature(
        bytes memory sig
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28, "Invalid signature 'v' value");
        return (v, r, s);
    }
}

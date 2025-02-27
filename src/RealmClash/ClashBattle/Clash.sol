// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Realm Clash Battle System
 * @dev Contract for managing turn-based PvP battles between character card NFTs, calculating combat outcomes based on stats, equipment and abilities
 * Handles battle mechanics including damage calculation, dodge chances, critical hits, and experience rewards
 */
interface ICharacterCard {
    struct CharacterStats {
        uint256 id;
        string name;
        uint8 strength;
        uint8 defense;
        uint8 agility;
        uint8 vitality;
        uint8 intelligence;
        uint8 magicPower;
        uint16 wins;
        uint16 losses;
        bool isVeteran;
        uint256 lastBattleTime;
        uint8 characterClass;
        uint256 weaponId;
        uint256 armorId;
        uint16 statPoints;
        uint256 experience;
    }

    function getCharacterStats(uint256 _tokenId) external view returns (CharacterStats memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function calculateHealth(uint256 _characterId) external view returns (uint256);
    function calculateDamage(uint256 _characterId) external view returns (uint256, bool, uint256);
    function calculateDefense(uint256 _characterId) external view returns (uint256);
    function calculateDodgeChance(uint256 _characterId) external view returns (uint256);
    function updateBattleResult(uint256 _characterId, bool _isWinner, uint256 _experienceGained) external;
    function getEffectiveIntelligence(uint256 _characterId) external view returns (uint256);
}

contract RealmClashBattleSystem {
    enum BattleState {
        Inactive,
        WaitingForOpponent,
        InProgress,
        Completed,
        Canceled
    }
    enum TurnState {
        NotStarted,
        Player1Turn,
        Player2Turn,
        TurnCompleted
    }

    struct BattleSnapshot {
        uint256 characterId;
        string name;
        uint256 maxHealth;
        uint256 currentHealth;
        uint256 attack;
        uint256 defense;
        uint256 dodgeChance;
        uint24 intelligence;
        bool hasForfeit;
    }

    struct Battle {
        uint256 battleId;
        address player1;
        address player2;
        uint256 characterId1;
        uint256 characterId2;
        BattleSnapshot snapshot1;
        BattleSnapshot snapshot2;
        BattleState state;
        uint256 startTime;
        uint256 lastActionTime;
        address winner;
        uint256 winningCharacterId;
        address currentTurnPlayer;
        TurnState turnState;
        uint8 player1AttackPoints;
        uint8 player2AttackPoints;
        bool player1TurnEnded;
        bool player2TurnEnded;
        uint256 turnNumber;
        uint256[] actionLog;
    }

    struct BattleAction {
        address player;
        uint256 timestamp;
        string actionType;
        uint256 value;
        bool critical;
        bool dodged;
    }

    address public owner;
    address public characterContractAddress;
    ICharacterCard public characterContract;

    uint256 public battleCounter;
    uint256 public actionLogCounter;
    mapping(uint256 => Battle) public battles;
    mapping(uint256 => BattleAction) public actionLogs;
    mapping(address => uint256) public activeBattlesByPlayer;

    address[] public waitingPlayers;
    mapping(address => uint256) public waitingPlayerCharacterIds;

    mapping(address => mapping(address => uint256)) public pendingChallenges;

    //// Track challengers for each player - can modify this to make it better
    // and track time, stake e.t.c
    mapping(address => address[]) public playerChallengers;
    mapping(address => address[]) public playerChallenges;

    //Rounding isnt really an issue since we are in test
    uint8 public constant MAX_ATTACK_POINTS = 13;
    uint8 public constant NORMAL_ATTACK_COST = 2;
    uint8 public constant SPECIAL_ATTACK1_COST = 3;
    uint8 public constant SPECIAL_ATTACK2_COST = 4;
    uint256 public BATTLE_TIMEOUT = 1 days;
    uint256 public TURN_TIMEOUT = 10 minutes;
    uint256 public constant NORMAL_ATTACK_MULTIPLIER = 150; // 150%
    uint256 public constant SPECIAL_ATTACK1_MULTIPLIER = 200; // 200%
    uint256 public constant SPECIAL_ATTACK2_MULTIPLIER = 250; // 250%

    uint256 public constant VICTORY_XP = 100;
    uint256 public constant FORFEIT_XP = 20;

    event BattleCreated(uint256 indexed battleId, address indexed player1, uint256 characterId1);
    event PlayerJoinedBattle(uint256 indexed battleId, address indexed player2, uint256 characterId2);
    event BattleStarted(uint256 indexed battleId, address player1, address player2);
    event TurnStarted(uint256 indexed battleId, address currentTurnPlayer, uint8 attackPoints);
    event AttackPerformed(
        uint256 indexed battleId, address attacker, string attackType, uint256 damage, bool critical, bool dodged
    );
    event TurnEnded(uint256 indexed battleId, address player);
    event BattleCompleted(
        uint256 indexed battleId, address winner, uint256 winningCharacterId, uint256 experienceGained
    );
    event BattleCanceled(uint256 indexed battleId, string reason);
    event PlayerForfeit(uint256 indexed battleId, address player);
    event ChallengeIssued(address indexed challenger, address indexed challenged, uint256 characterId);
    event ChallengeAccepted(address indexed challenger, address indexed challenged, uint256 battleId);
    event ChallengeRejected(address indexed challenger, address indexed challenged);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier characterOwner(uint256 _characterId) {
        require(characterContract.ownerOf(_characterId) == msg.sender, "You don't own this character");
        _;
    }

    modifier activeBattle(uint256 _battleId) {
        require(battles[_battleId].state == BattleState.InProgress, "Battle is not active");
        _;
    }

    modifier playerInBattle(uint256 _battleId) {
        require(
            battles[_battleId].player1 == msg.sender || battles[_battleId].player2 == msg.sender,
            "You are not part of this battle"
        );
        _;
    }

    modifier currentTurnPlayer(uint256 _battleId) {
        require(battles[_battleId].currentTurnPlayer == msg.sender, "Not your turn");
        _;
    }

    constructor(address _characterContractAddress) {
        owner = msg.sender;
        characterContractAddress = _characterContractAddress;
        characterContract = ICharacterCard(_characterContractAddress);
    }

    function joinMatchmaking(uint256 _characterId) external characterOwner(_characterId) {
        require(activeBattlesByPlayer[msg.sender] == 0, "Already in an active battle");

        for (uint256 i = 0; i < waitingPlayers.length; i++) {
            if (waitingPlayers[i] == msg.sender) {
                waitingPlayers[i] = waitingPlayers[waitingPlayers.length - 1];
                waitingPlayers.pop();
                break;
            }
        }

        waitingPlayers.push(msg.sender);
        waitingPlayerCharacterIds[msg.sender] = _characterId;

        _tryMatchmaking();
    }

    function _tryMatchmaking() internal {
        if (waitingPlayers.length >= 2) {
            address player1 = waitingPlayers[waitingPlayers.length - 2];
            address player2 = waitingPlayers[waitingPlayers.length - 1];

            uint256 characterId1 = waitingPlayerCharacterIds[player1];
            uint256 characterId2 = waitingPlayerCharacterIds[player2];

            _createBattle(player1, player2, characterId1, characterId2);

            waitingPlayers.pop();
            waitingPlayers.pop();

            delete waitingPlayerCharacterIds[player1];
            delete waitingPlayerCharacterIds[player2];
        }
    }

    function leaveMatchmaking() external {
        for (uint256 i = 0; i < waitingPlayers.length; i++) {
            if (waitingPlayers[i] == msg.sender) {
                waitingPlayers[i] = waitingPlayers[waitingPlayers.length - 1];
                waitingPlayers.pop();
                delete waitingPlayerCharacterIds[msg.sender];
                break;
            }
        }
    }

    function challengePlayer(address _opponent, uint256 _characterId) external characterOwner(_characterId) {
        require(_opponent != msg.sender, "Cannot challenge yourself");
        require(activeBattlesByPlayer[msg.sender] == 0, "You are already in a battle");
        require(activeBattlesByPlayer[_opponent] == 0, "Opponent is already in a battle");

        pendingChallenges[msg.sender][_opponent] = _characterId;

        // Add to tracking arrays
        playerChallengers[_opponent].push(msg.sender);
        playerChallenges[msg.sender].push(_opponent);

        emit ChallengeIssued(msg.sender, _opponent, _characterId);
    }

    // Modify acceptChallenge to clean up the arrays
    function acceptChallenge(address _challenger, uint256 _characterId) external characterOwner(_characterId) {
        require(pendingChallenges[_challenger][msg.sender] > 0, "No challenge from this player");
        require(activeBattlesByPlayer[msg.sender] == 0, "You are already in a battle");
        require(activeBattlesByPlayer[_challenger] == 0, "Challenger is already in a battle");

        uint256 challengerCharacterId = pendingChallenges[_challenger][msg.sender];

        uint256 battleId = _createBattle(_challenger, msg.sender, challengerCharacterId, _characterId);

        // Clean up challenge data
        delete pendingChallenges[_challenger][msg.sender];
        _removeFromArray(playerChallengers[msg.sender], _challenger);
        _removeFromArray(playerChallenges[_challenger], msg.sender);

        emit ChallengeAccepted(_challenger, msg.sender, battleId);
    }

    function _removeFromArray(address[] storage array, address value) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                array[i] = array[array.length - 1];
                array.pop();
                break;
            }
        }
    }

    function getPlayerChallengers(address _player) external view returns (address[] memory) {
        return playerChallengers[_player];
    }

    function getPlayerChallenges(address _player) external view returns (address[] memory) {
        return playerChallenges[_player];
    }

    function getChallengeDetails(address _challenger, address _opponent) external view returns (uint256 characterId) {
        return pendingChallenges[_challenger][_opponent];
    }

    function rejectChallenge(address _challenger) external {
        require(pendingChallenges[_challenger][msg.sender] > 0, "No challenge from this player");

        delete pendingChallenges[_challenger][msg.sender];
        _removeFromArray(playerChallengers[msg.sender], _challenger);
        _removeFromArray(playerChallenges[_challenger], msg.sender);
        emit ChallengeRejected(_challenger, msg.sender);
    }

    function _createBattle(address _player1, address _player2, uint256 _characterId1, uint256 _characterId2)
        internal
        returns (uint256)
    {
        battleCounter++;
        uint256 newBattleId = battleCounter;

        Battle storage battle = battles[newBattleId];
        battle.battleId = newBattleId;
        battle.player1 = _player1;
        battle.player2 = _player2;
        battle.characterId1 = _characterId1;
        battle.characterId2 = _characterId2;
        battle.state = BattleState.InProgress;
        battle.startTime = block.timestamp;
        battle.lastActionTime = block.timestamp;
        battle.turnNumber = 1;

        _createBattleSnapshots(battle);

        _determineFirstTurn(battle);

        activeBattlesByPlayer[_player1] = newBattleId;
        activeBattlesByPlayer[_player2] = newBattleId;

        emit BattleCreated(newBattleId, _player1, _characterId1);
        emit PlayerJoinedBattle(newBattleId, _player2, _characterId2);
        emit BattleStarted(newBattleId, _player1, _player2);

        return newBattleId;
    }

    function _createBattleSnapshots(Battle storage battle) internal {
        ICharacterCard.CharacterStats memory stats1 = characterContract.getCharacterStats(battle.characterId1);
        uint256 health1 = characterContract.calculateHealth(battle.characterId1);
        uint256 defense1 = characterContract.calculateDefense(battle.characterId1);
        uint256 dodgeChance1 = characterContract.calculateDodgeChance(battle.characterId1);
        (uint256 attack1,,) = characterContract.calculateDamage(battle.characterId1);
        uint24 intelligence1 = uint24(characterContract.getEffectiveIntelligence(battle.characterId1));

        battle.snapshot1 = BattleSnapshot({
            characterId: battle.characterId1,
            name: stats1.name,
            maxHealth: health1,
            currentHealth: health1,
            attack: attack1,
            defense: defense1,
            dodgeChance: dodgeChance1,
            intelligence: intelligence1,
            hasForfeit: false
        });

        ICharacterCard.CharacterStats memory stats2 = characterContract.getCharacterStats(battle.characterId2);
        uint256 health2 = characterContract.calculateHealth(battle.characterId2);
        uint256 defense2 = characterContract.calculateDefense(battle.characterId2);
        uint256 dodgeChance2 = characterContract.calculateDodgeChance(battle.characterId2);
        (uint256 attack2,,) = characterContract.calculateDamage(battle.characterId2);
        uint24 intelligence2 = uint24(characterContract.getEffectiveIntelligence(battle.characterId2));

        battle.snapshot2 = BattleSnapshot({
            characterId: battle.characterId2,
            name: stats2.name,
            maxHealth: health2,
            currentHealth: health2,
            attack: attack2,
            defense: defense2,
            dodgeChance: dodgeChance2,
            intelligence: intelligence2,
            hasForfeit: false
        });
    }

    function _determineFirstTurn(Battle storage battle) internal {
        if (battle.snapshot1.intelligence >= battle.snapshot2.intelligence) {
            battle.currentTurnPlayer = battle.player1;
            battle.turnState = TurnState.Player1Turn;
        } else {
            battle.currentTurnPlayer = battle.player2;
            battle.turnState = TurnState.Player2Turn;
        }
        battle.player1AttackPoints = uint8(_generateAttackPoints(battle.snapshot1.intelligence));
        battle.player2AttackPoints = uint8(_generateAttackPoints(battle.snapshot2.intelligence));

        emit TurnStarted(
            battle.battleId,
            battle.currentTurnPlayer,
            battle.currentTurnPlayer == battle.player1 ? battle.player1AttackPoints : battle.player2AttackPoints
        );
    }

    function _generateAttackPoints(uint24 intelligence) internal view returns (uint24) {
        uint256 rand = _pseudoRandomNumber(intelligence) % 15;
        uint24 basePoints = uint24(4 + rand);

        uint24 intBonus = uint24((intelligence * 4) / 255);

        uint24 totalPoints = uint24(basePoints + intBonus);
        if (totalPoints > MAX_ATTACK_POINTS) {
            totalPoints = MAX_ATTACK_POINTS;
        }

        return totalPoints;
    }

    function performAttack(uint256 _battleId, uint8 _attackType)
        external
        activeBattle(_battleId)
        currentTurnPlayer(_battleId)
    {
        Battle storage battle = battles[_battleId];

        if (
            (battle.turnState == TurnState.Player1Turn && battle.player1TurnEnded)
                || (battle.turnState == TurnState.Player2Turn && battle.player2TurnEnded)
        ) {
            revert("You've already ended your turn");
        }

        bool isPlayer1 = (msg.sender == battle.player1);
        uint8 attackCost;
        string memory attackTypeStr;
        uint256 damageMultiplier;

        if (_attackType == 1) {
            attackCost = NORMAL_ATTACK_COST;
            attackTypeStr = "normal";
            damageMultiplier = NORMAL_ATTACK_MULTIPLIER;
        } else if (_attackType == 2) {
            attackCost = SPECIAL_ATTACK1_COST;
            attackTypeStr = "special1";
            damageMultiplier = SPECIAL_ATTACK1_MULTIPLIER;
        } else if (_attackType == 3) {
            attackCost = SPECIAL_ATTACK2_COST;
            attackTypeStr = "special2";
            damageMultiplier = SPECIAL_ATTACK2_MULTIPLIER;
        } else {
            revert("Invalid attack type");
        }

        uint8 playerAttackPoints = isPlayer1 ? battle.player1AttackPoints : battle.player2AttackPoints;
        require(playerAttackPoints >= attackCost, "Not enough attack points");

        // Deduct points
        if (isPlayer1) {
            battle.player1AttackPoints -= attackCost;
        } else {
            battle.player2AttackPoints -= attackCost;
        }

        BattleSnapshot storage attacker = isPlayer1 ? battle.snapshot1 : battle.snapshot2;
        BattleSnapshot storage defender = isPlayer1 ? battle.snapshot2 : battle.snapshot1;

        (uint256 damage, bool isCritical) =
            _calculateBattleDamage(attacker.attack, defender.defense, attacker.intelligence, damageMultiplier);

        bool isDodged = _checkDodge(defender.dodgeChance);

        if (!isDodged) {
            if (damage >= defender.currentHealth) {
                defender.currentHealth = 0;
            } else {
                defender.currentHealth -= damage;
            }
        } else {
            damage = 0;
        }

        _recordBattleAction(battle, msg.sender, attackTypeStr, damage, isCritical, isDodged);

        emit AttackPerformed(_battleId, msg.sender, attackTypeStr, damage, isCritical, isDodged);

        if (defender.currentHealth == 0) {
            _endBattle(_battleId, isPlayer1);
            return;
        }

        // Switch turns after attack only if other player hasn't ended their turn
        if (isPlayer1) {
            if (!battle.player1TurnEnded && !battle.player2TurnEnded) {
                battle.turnState = TurnState.Player2Turn;
                battle.currentTurnPlayer = battle.player2;
            }
        } else {
            if (!battle.player2TurnEnded && !battle.player1TurnEnded) {
                battle.turnState = TurnState.Player1Turn;
                battle.currentTurnPlayer = battle.player1;
            }
        }

        emit TurnStarted(
            battle.battleId,
            battle.currentTurnPlayer,
            battle.currentTurnPlayer == battle.player1 ? battle.player1AttackPoints : battle.player2AttackPoints
        );

        battle.lastActionTime = block.timestamp;
    }

    function endTurn(uint256 _battleId) external activeBattle(_battleId) currentTurnPlayer(_battleId) {
        Battle storage battle = battles[_battleId];

        bool isPlayer1 = (msg.sender == battle.player1);

        if (isPlayer1) {
            require(battle.turnState == TurnState.Player1Turn, "Not your turn");
            battle.player1TurnEnded = true;

            if (!(battle.player1TurnEnded && battle.player2TurnEnded)) {
                battle.turnState = TurnState.Player2Turn;
                battle.currentTurnPlayer = battle.player2;
            }
        } else {
            require(battle.turnState == TurnState.Player2Turn, "Not your turn");
            battle.player2TurnEnded = true;
            if (!(battle.player1TurnEnded && battle.player2TurnEnded)) {
                battle.turnState = TurnState.Player1Turn;
                battle.currentTurnPlayer = battle.player1;
            }
        }

        // Start new turn if both players have ended their turns
        if (battle.player1TurnEnded && battle.player2TurnEnded) {
            // No need to switch turns again before calling _startNewTurn
            // _startNewTurn will handle the turn switching correctly
            _startNewTurn(_battleId);
        } else {
            emit TurnStarted(
                battle.battleId,
                battle.currentTurnPlayer,
                battle.currentTurnPlayer == battle.player1 ? battle.player1AttackPoints : battle.player2AttackPoints
            );
        }

        _recordBattleAction(battle, msg.sender, "endTurn", 0, false, false);
        emit TurnEnded(_battleId, msg.sender);

        battle.lastActionTime = block.timestamp;
    }

    function _startNewTurn(uint256 _battleId) internal {
        Battle storage battle = battles[_battleId];

        battle.turnNumber++;
        battle.player1TurnEnded = false;
        battle.player2TurnEnded = false;

        battle.player1AttackPoints = uint8(_generateAttackPoints(battle.snapshot1.intelligence));
        battle.player2AttackPoints = uint8(_generateAttackPoints(battle.snapshot2.intelligence));

        if (battle.currentTurnPlayer == battle.player1) {
            battle.turnState = TurnState.Player2Turn;
            battle.currentTurnPlayer = battle.player2;
        } else {
            battle.turnState = TurnState.Player1Turn;
            battle.currentTurnPlayer = battle.player1;
        }

        emit TurnStarted(
            battle.battleId,
            battle.currentTurnPlayer,
            battle.currentTurnPlayer == battle.player1 ? battle.player1AttackPoints : battle.player2AttackPoints
        );
    }

    function forfeitBattle(uint256 _battleId) external activeBattle(_battleId) playerInBattle(_battleId) {
        Battle storage battle = battles[_battleId];

        bool isPlayer1Forfeiting = (msg.sender == battle.player1);

        if (isPlayer1Forfeiting) {
            battle.snapshot1.hasForfeit = true;
        } else {
            battle.snapshot2.hasForfeit = true;
        }

        _recordBattleAction(battle, msg.sender, "forfeit", 0, false, false);

        emit PlayerForfeit(_battleId, msg.sender);

        _endBattle(_battleId, !isPlayer1Forfeiting);
    }

    function _endBattle(uint256 _battleId, bool _isPlayer1Winner) internal {
        Battle storage battle = battles[_battleId];

        battle.state = BattleState.Completed;

        address winner;
        uint256 winningCharacterId;
        uint256 experienceGained;

        if (_isPlayer1Winner) {
            winner = battle.player1;
            winningCharacterId = battle.characterId1;
        } else {
            winner = battle.player2;
            winningCharacterId = battle.characterId2;
        }

        battle.winner = winner;
        battle.winningCharacterId = winningCharacterId;

        bool wasForfeit = (battle.snapshot1.hasForfeit || battle.snapshot2.hasForfeit);
        experienceGained = wasForfeit ? FORFEIT_XP : VICTORY_XP;

        characterContract.updateBattleResult(winningCharacterId, true, experienceGained);

        uint256 losingCharacterId = _isPlayer1Winner ? battle.characterId2 : battle.characterId1;
        characterContract.updateBattleResult(losingCharacterId, false, wasForfeit ? FORFEIT_XP : VICTORY_XP / 2);

        delete activeBattlesByPlayer[battle.player1];
        delete activeBattlesByPlayer[battle.player2];

        emit BattleCompleted(_battleId, winner, winningCharacterId, experienceGained);
    }

    function checkBattleTimeout(uint256 _battleId) external {
        Battle storage battle = battles[_battleId];
        require(battle.state == BattleState.InProgress, "Battle is not in progress");

        if (block.timestamp > battle.lastActionTime + BATTLE_TIMEOUT) {
            _cancelBattle(_battleId, "Battle timed out");
        }
    }

    function checkTurnTimeout(uint256 _battleId) external {
        Battle storage battle = battles[_battleId];
        require(battle.state == BattleState.InProgress, "Battle is not in progress");

        if (block.timestamp > battle.lastActionTime + TURN_TIMEOUT) {
            address inactivePlayer = battle.currentTurnPlayer;
            bool isPlayer1Inactive = (inactivePlayer == battle.player1);

            if (isPlayer1Inactive) {
                battle.snapshot1.hasForfeit = true;
            } else {
                battle.snapshot2.hasForfeit = true;
            }

            _recordBattleAction(battle, inactivePlayer, "timeout", 0, false, false);

            _endBattle(_battleId, !isPlayer1Inactive);
        }
    }

    function _cancelBattle(uint256 _battleId, string memory reason) internal {
        Battle storage battle = battles[_battleId];

        battle.state = BattleState.Canceled;

        delete activeBattlesByPlayer[battle.player1];
        delete activeBattlesByPlayer[battle.player2];

        emit BattleCanceled(_battleId, reason);
    }

    function _calculateBattleDamage(
        uint256 _attackStat,
        uint256 _defenseStat,
        uint24 _intelligence,
        uint256 _damageMultiplier
    ) public view returns (uint256 finalDamage, bool isCritical) {
        uint256 baseDamage;

        // Progressive defense reduction - higher defense reduces damage more effectively
        uint256 defenseRatio = (_defenseStat * 100) / (_attackStat + 1); // Prevent division by zero
        uint256 damageReduction = (defenseRatio * 80) / 100; // Up to 80% reduction based on defense ratio

        if (damageReduction > 80) damageReduction = 80; // Cap at 80% reduction

        baseDamage = (_attackStat * (100 - damageReduction)) / 100;

        uint256 critChance = 5 + (_intelligence * 10) / 100;
        if (critChance > 30) critChance = 30;

        isCritical = _pseudoRandomNumber(_intelligence) % 100 < critChance;

        uint256 modifiedDamage = (baseDamage * _damageMultiplier) / 100;
        modifiedDamage = (modifiedDamage * 50) / 100 + modifiedDamage;

        if (isCritical) {
            modifiedDamage = (modifiedDamage * 150) / 100;
        }

        uint256 randomFactor = 85 + (_pseudoRandomNumber(_intelligence + 1) % 35); // 85-120% arena effect
        finalDamage = (modifiedDamage * randomFactor) / 100;

        if (finalDamage < 1) {
            finalDamage = 1;
        }
        return (finalDamage, isCritical);
    }

    function _checkDodge(uint256 _dodgeChance) internal view returns (bool) {
        uint256 randNum = _pseudoRandomNumber(block.timestamp) % 100;
        return randNum < _dodgeChance;
    }

    function _pseudoRandomNumber(uint256 seed) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp, seed)));
    }

    function _recordBattleAction(
        Battle storage battle,
        address player,
        string memory actionType,
        uint256 value,
        bool critical,
        bool dodged
    ) internal {
        actionLogCounter++;
        uint256 actionId = actionLogCounter;

        actionLogs[actionId] = BattleAction({
            player: player,
            timestamp: block.timestamp,
            actionType: actionType,
            value: value,
            critical: critical,
            dodged: dodged
        });

        battle.actionLog.push(actionId);
    }

    function getActiveBattle(address _player) external view returns (uint256) {
        return activeBattlesByPlayer[_player];
    }

    function getBattleActionLog(uint256 _battleId) external view returns (BattleAction[] memory) {
        Battle storage battle = battles[_battleId];
        BattleAction[] memory actions = new BattleAction[](battle.actionLog.length);

        for (uint256 i = 0; i < battle.actionLog.length; i++) {
            actions[i] = actionLogs[battle.actionLog[i]];
        }

        return actions;
    }

    function getCurrentTurnInfo(uint256 _battleId)
        external
        view
        returns (address currentPlayer, uint8 remainingAttackPoints, bool turnEnded)
    {
        Battle storage battle = battles[_battleId];
        bool isPlayer1Turn = (battle.turnState == TurnState.Player1Turn);

        return (
            battle.currentTurnPlayer,
            isPlayer1Turn ? battle.player1AttackPoints : battle.player2AttackPoints,
            isPlayer1Turn ? battle.player1TurnEnded : battle.player2TurnEnded
        );
    }

    function getWaitingPlayers() external view returns (address[] memory players, uint256[] memory characterIds) {
        players = new address[](waitingPlayers.length);
        characterIds = new uint256[](waitingPlayers.length);

        for (uint256 i = 0; i < waitingPlayers.length; i++) {
            players[i] = waitingPlayers[i];
            characterIds[i] = waitingPlayerCharacterIds[waitingPlayers[i]];
        }

        return (players, characterIds);
    }

    function getPendingChallenge(address _challenger, address _challenged) external view returns (uint256) {
        return pendingChallenges[_challenger][_challenged];
    }

    function emergencyCancelBattle(uint256 _battleId) external onlyOwner {
        Battle storage battle = battles[_battleId];
        require(battle.state == BattleState.InProgress, "Battle is not in progress");

        _cancelBattle(_battleId, "Emergency cancellation by admin");
    }

    function setCharacterContract(address _newAddress) external onlyOwner {
        characterContractAddress = _newAddress;
        characterContract = ICharacterCard(_newAddress);
    }

    function updateBattleTimeout(uint256 _newTimeout) external onlyOwner {
        BATTLE_TIMEOUT = _newTimeout;
    }

    function updateTurnTimeout(uint256 _newTimeout) external onlyOwner {
        TURN_TIMEOUT = _newTimeout;
    }

    function getBattleProgress(uint256 _battleId)
        external
        view
        returns (
            uint256 player1Health,
            uint256 player1MaxHealth,
            uint256 player2Health,
            uint256 player2MaxHealth,
            uint256 turnsCompleted,
            uint256 totalDamageDealt
        )
    {
        Battle storage battle = battles[_battleId];

        uint256 totalDamage = 0;
        for (uint256 i = 0; i < battle.actionLog.length; i++) {
            BattleAction memory action = actionLogs[battle.actionLog[i]];
            if (
                keccak256(bytes(action.actionType)) == keccak256(bytes("normal"))
                    || keccak256(bytes(action.actionType)) == keccak256(bytes("special1"))
                    || keccak256(bytes(action.actionType)) == keccak256(bytes("special2"))
            ) {
                totalDamage += action.value;
            }
        }

        return (
            battle.snapshot1.currentHealth,
            battle.snapshot1.maxHealth,
            battle.snapshot2.currentHealth,
            battle.snapshot2.maxHealth,
            battle.turnNumber,
            totalDamage
        );
    }

    function getPlayerStatus(uint256 _battleId, address _player)
        external
        view
        returns (
            uint256 currentHealth,
            uint256 maxHealth,
            uint256 attackPoints,
            bool hasTurnEnded,
            uint256 damageDealt,
            uint256 damageReceived
        )
    {
        Battle storage battle = battles[_battleId];
        require(_player == battle.player1 || _player == battle.player2, "Player not in battle");

        bool isPlayer1 = (_player == battle.player1);
        BattleSnapshot storage playerSnapshot = isPlayer1 ? battle.snapshot1 : battle.snapshot2;

        uint256 dealtDamage = 0;
        uint256 receivedDamage = 0;

        for (uint256 i = 0; i < battle.actionLog.length; i++) {
            BattleAction memory action = actionLogs[battle.actionLog[i]];

            if (
                keccak256(bytes(action.actionType)) == keccak256(bytes("normal"))
                    || keccak256(bytes(action.actionType)) == keccak256(bytes("special1"))
                    || keccak256(bytes(action.actionType)) == keccak256(bytes("special2"))
            ) {
                if (action.player == _player) {
                    dealtDamage += action.value;
                } else {
                    receivedDamage += action.value;
                }
            }
        }

        return (
            playerSnapshot.currentHealth,
            playerSnapshot.maxHealth,
            isPlayer1 ? battle.player1AttackPoints : battle.player2AttackPoints,
            isPlayer1 ? battle.player1TurnEnded : battle.player2TurnEnded,
            dealtDamage,
            receivedDamage
        );
    }

    function getBattleSnapshots(uint256 _battleId)
        external
        view
        returns (BattleSnapshot memory snapshot1, BattleSnapshot memory snapshot2)
    {
        Battle storage battle = battles[_battleId];
        return (battle.snapshot1, battle.snapshot2);
    }

    function getBattleDetails(uint256 _battleId)
        external
        view
        returns (
            address player1,
            address player2,
            uint256 characterId1,
            uint256 characterId2,
            BattleState state,
            uint256 startTime,
            address winner,
            address _currentTurnPlayer,
            TurnState turnState,
            uint256 turnNumber,
            uint256 player1AttackPoints,
            uint256 player2AttackPoints
        )
    {
        Battle storage battle = battles[_battleId];
        return (
            battle.player1,
            battle.player2,
            battle.characterId1,
            battle.characterId2,
            battle.state,
            battle.startTime,
            battle.winner,
            battle.currentTurnPlayer,
            battle.turnState,
            battle.turnNumber,
            battle.player1AttackPoints,
            battle.player2AttackPoints
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBase.sol";

/**
 * @title RealmClash-RNGCombat
 * @dev A PvP turn-based combat game where players battle warriors against each other with a random outcome based on warriors stats points
 */
contract RealmClashRNGCombat is ERC721Enumerable, Ownable, VRFConsumerBase {
    uint256 public _tokenIdsCounter;
    uint256 public _battleIdsCounter;

    bytes32 internal keyHash;
    uint256 internal fee;

    uint256 public constant VETERAN_THRESHOLD = 10;
    uint256 public constant MINT_PRICE = 0 ether; //Testing
    uint256 public constant BATTLE_FEE = 0 ether; //Testing

    uint8 public constant MIN_STAT = 1;
    uint8 public constant MAX_STAT = 100;
    uint8 public constant STAT_POINTS = 200;

    struct Warrior {
        uint256 id;
        string name;
        uint8 strength;
        uint8 defense;
        uint8 agility;
        uint8 vitality;
        uint8 intelligence;
        uint16 wins;
        uint16 losses;
        bool isVeteran;
        uint256 lastBattleTime;
    }

    struct Battle {
        uint256 id;
        uint256 challenger;
        uint256 defender;
        uint256 winner;
        uint256 timestamp;
        bool completed;
    }

    mapping(uint256 => Warrior) public warriors;
    mapping(uint256 => uint256) public battleCooldowns;
    mapping(uint256 => Battle) public battles;
    mapping(bytes32 => uint256) public requestToBattle;

    event WarriorCreated(
        uint256 indexed id,
        address indexed owner,
        string name
    );
    event BattleInitiated(
        uint256 indexed battleId,
        uint256 indexed challengerId,
        uint256 indexed defenderId,
        bytes32 initiateBattled
    );
    event BattleCompleted(
        uint256 indexed battleId,
        uint256 indexed winner,
        uint256 indexed loser
    );
    event VeteranStatusAchieved(uint256 indexed warriorId);

    uint256 public constant BATTLE_COOLDOWN = 1 hours;

    constructor(
        address vrfCoordinator,
        address linkToken,
        bytes32 _keyHash,
        uint256 _fee
    )
        ERC721("Warrior Combat", "WARRIOR")
        VRFConsumerBase(vrfCoordinator, linkToken)
        Ownable(msg.sender)
    {
        keyHash = _keyHash;
        fee = _fee;
    }

    function createWarrior(
        string memory name,
        uint8 strength,
        uint8 defense,
        uint8 agility,
        uint8 vitality,
        uint8 intelligence
    ) external payable returns (uint256) {
        require(msg.value >= MINT_PRICE, "Insufficient payment");
        require(
            strength >= MIN_STAT &&
                defense >= MIN_STAT &&
                agility >= MIN_STAT &&
                vitality >= MIN_STAT &&
                intelligence >= MIN_STAT,
            "Stats below minimum"
        );
        require(
            strength <= MAX_STAT &&
                defense <= MAX_STAT &&
                agility <= MAX_STAT &&
                vitality <= MAX_STAT &&
                intelligence <= MAX_STAT,
            "Stats above maximum"
        );
        require(
            strength + defense + agility + vitality + intelligence ==
                STAT_POINTS,
            "Must use exactly 200 stat points"
        );
        uint256 newWarriorId = ++_tokenIdsCounter;
        _safeMint(msg.sender, newWarriorId);
        warriors[newWarriorId] = Warrior({
            id: newWarriorId,
            name: name,
            strength: strength,
            defense: defense,
            agility: agility,
            vitality: vitality,
            intelligence: intelligence,
            wins: 0,
            losses: 0,
            isVeteran: false,
            lastBattleTime: 0
        });
        emit WarriorCreated(newWarriorId, msg.sender, name);
        return newWarriorId;
    }

    function initiateBattle(
        uint256 challengerId,
        uint256 defenderId
    ) external payable {
        require(msg.value >= BATTLE_FEE, "Insufficient battle fee");
        require(ownerOf(challengerId) == msg.sender, "Not owner of challenger");
        require(
            ownerOf(challengerId) != ownerOf(defenderId),
            "Cannot battle your own warrior"
        );
        if (warriors[challengerId].lastBattleTime != 0) {
            require(
                block.timestamp >=
                    warriors[challengerId].lastBattleTime + BATTLE_COOLDOWN,
                "Challenger on cooldown"
            );
        }
        if (warriors[defenderId].lastBattleTime != 0) {
            require(
                block.timestamp >=
                    warriors[defenderId].lastBattleTime + BATTLE_COOLDOWN,
                "Defender on cooldown"
            );
        }

        warriors[challengerId].lastBattleTime = block.timestamp;
        warriors[defenderId].lastBattleTime = block.timestamp;
        uint256 battleId = ++_battleIdsCounter;
        battles[battleId] = Battle({
            id: battleId,
            challenger: challengerId,
            defender: defenderId,
            winner: 0,
            timestamp: block.timestamp,
            completed: false
        });
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK for VRF"
        );
        bytes32 requestId = requestRandomness(keyHash, fee);
        requestToBattle[requestId] = battleId;
        emit BattleInitiated(battleId, challengerId, defenderId, requestId);
    }

    function fulfillRandomness(
        bytes32 requestId,
        uint256 randomness
    ) internal override {
        uint256 battleId = requestToBattle[requestId];
        emit BattleInitiated(0, 0, battleId, requestId);
        require(battleId > 0, "Battle not found");
        Battle storage battle = battles[battleId];
        require(!battle.completed, "Battle already completed");
        uint256 challengerId = battle.challenger;
        uint256 defenderId = battle.defender;
        Warrior storage challenger = warriors[challengerId];
        Warrior storage defender = warriors[defenderId];
        uint256 winnerTokenId = _determineWinner(
            challenger,
            defender,
            randomness
        );
        battle.winner = winnerTokenId;
        battle.completed = true;
        if (winnerTokenId == challengerId) {
            challenger.wins++;
            defender.losses++;
            if (challenger.wins >= VETERAN_THRESHOLD && !challenger.isVeteran) {
                challenger.isVeteran = true;
                emit VeteranStatusAchieved(challengerId);
            }
        } else {
            defender.wins++;
            challenger.losses++;
            if (defender.wins >= VETERAN_THRESHOLD && !defender.isVeteran) {
                defender.isVeteran = true;
                emit VeteranStatusAchieved(defenderId);
            }
        }
        emit BattleCompleted(
            battleId,
            winnerTokenId,
            winnerTokenId == challengerId ? defenderId : challengerId
        );
    }

    function _determineWinner(
        Warrior storage challenger,
        Warrior storage defender,
        uint256 randomness
    ) private view returns (uint256) {
        uint256 challengerAttackPower = _calculateAttackPower(
            challenger.strength,
            challenger.agility,
            challenger.intelligence,
            uint16(randomness % 1000)
        );
        uint256 defenderDefensePower = _calculateDefensePower(
            defender.defense,
            defender.agility,
            defender.vitality,
            uint16((randomness / 1000) % 1000)
        );
        uint256 damageToDefender = challengerAttackPower > defenderDefensePower
            ? challengerAttackPower - defenderDefensePower
            : 1;
        uint256 defenderAttackPower = _calculateAttackPower(
            defender.strength,
            defender.agility,
            defender.intelligence,
            uint16((randomness / 1000000) % 1000)
        );
        uint256 challengerDefensePower = _calculateDefensePower(
            challenger.defense,
            challenger.agility,
            challenger.vitality,
            uint16((randomness / 1000000000) % 1000)
        );
        uint256 damageToChallenger = defenderAttackPower >
            challengerDefensePower
            ? defenderAttackPower - challengerDefensePower
            : 1;
        uint256 challengerHP = challenger.vitality * 10;
        uint256 defenderHP = defender.vitality * 10;
        uint256 hitsTillChallengerDefeated = challengerHP / damageToChallenger;
        uint256 hitsTillDefenderDefeated = defenderHP / damageToDefender;
        if (hitsTillChallengerDefeated >= hitsTillDefenderDefeated) {
            return challenger.id;
        } else {
            return defender.id;
        }
    }

    function _calculateAttackPower(
        uint8 strength,
        uint8 agility,
        uint8 intelligence,
        uint16 randFactor
    ) private pure returns (uint256) {
        uint256 baseDamage = strength * 5;
        uint256 hitChance = 70 + ((agility * 25) / 100);
        uint256 critChance = 5 + ((intelligence * 20) / 100);
        bool hits = (randFactor % 100) < hitChance;
        if (!hits) return 0;
        bool isCritical = ((randFactor / 100) % 100) < critChance;
        return isCritical ? baseDamage * 2 : baseDamage;
    }

    function _calculateDefensePower(
        uint8 defense,
        uint8 agility,
        uint8 vitality,
        uint16 randFactor
    ) private pure returns (uint256) {
        uint256 baseDefense = defense * 3;
        uint256 dodgeChance = 5 + ((agility * 20) / 100);
        uint256 vitalityBonus = (vitality * 20) / 100;
        bool dodges = (randFactor % 100) < dodgeChance;
        if (dodges) return 10000;
        return baseDefense + ((baseDefense * vitalityBonus) / 100);
    }

    function getWarrior(
        uint256 warriorId
    ) external view returns (Warrior memory) {
        require(warriors[warriorId].id != 0, "Warrior does not exist");
        return warriors[warriorId];
    }

    function getBattle(uint256 battleId) external view returns (Battle memory) {
        require(battleId <= _battleIdsCounter, "Battle does not exist");
        return battles[battleId];
    }

    function getWarriorsByOwner(
        address owner
    ) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory result = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            result[i] = tokenOfOwnerByIndex(owner, i);
        }

        return result;
    }
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Withdrawal failed");
    }
    function withdrawLink(uint256 amount) external onlyOwner {
        require(LINK.transfer(owner(), amount), "LINK transfer failed");
    }
}

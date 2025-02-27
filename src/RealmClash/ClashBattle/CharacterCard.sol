// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

/**
 * @title Realm Clash Character Cards
 * @dev NFT contract for minting and managing warrior character cards with customizable stats, equipment, and battle capabilities
 */
interface WeaponInterface {
    struct WeaponStats {
        uint256 id;
        string name;
        uint8 damageBonus;
        uint8 defenseBonus;
        uint8 agilityBonus;
        uint8 vitalityBonus;
        uint8 intelligenceBonus;
        uint8 magicPowerBonus;
        uint256 equippedCharacterId;
    }

    function getWeaponStats(
        uint256 _weaponId
    ) external view returns (WeaponStats memory);
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface ArmorInterface {
    struct ArmorStats {
        uint256 id;
        string name;
        uint8 damageBonus;
        uint8 defenseBonus;
        uint8 agilityBonus;
        uint8 vitalityBonus;
        uint8 intelligenceBonus;
        uint8 magicPowerBonus;
        uint256 equippedCharacterId;
    }

    function getArmorStats(
        uint256 _armorId
    ) external view returns (ArmorStats memory);
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract CharacterCard is ERC721, ERC721Enumerable, ERC721URIStorage {
    uint256 public _tokenIdCounter;
    mapping(address => bool) public _allowedMinters;
    address public weaponContractAddress;
    address public armorContractAddress;

    enum CharacterClass {
        Human, //0 Balanced, needs stat points to evolve
        King, //1 High strength, high vitality, low magic, medium defense
        Mage, //2 Low strength, high magic power, high intelligence, low defense
        Archer, //3 High agility, medium strength, low defense, medium intelligence
        Knight, //4 High strength, high defense, low magic, low intelligence
        Demon, //5 High strength, high magic, low defense, low intelligence
        God //6 Balanced high stats, no weaknesses, overpowered
    }

    struct CharacterStats {
        uint256 id;
        string name;
        uint8 strength; // Physical damage (0-255) - Most effective for Knight, King, Demon
        uint8 defense; // Damage reduction (0-255) - Most effective for Knight, King
        uint8 agility; // Attack speed, dodge (0-255) - Most effective for Archer
        uint8 vitality; // Health points (0-255) - Most effective for King, Knight
        uint8 intelligence; // Critical hits, magic efficiency (0-255) - Most effective for Mage
        uint8 magicPower; // Magic damage (0-255) - Most effective for Mage, God, Demon
        uint16 wins;
        uint16 losses;
        bool isVeteran;
        uint256 lastBattleTime;
        CharacterClass characterClass;
        uint256 weaponId;
        uint256 armorId;
        uint16 statPoints; // Available points to spend on stats
        uint256 experience; // Total experience points earned
    }

    struct ClassMultipliers {
        uint8 strengthMulti; // Base strength effectiveness (%)
        uint8 defenseMulti; // Base defense effectiveness (%)
        uint8 agilityMulti; // Base agility effectiveness (%)
        uint8 vitalityMulti; // Base vitality effectiveness (%)
        uint8 intelligenceMulti; // Base intelligence effectiveness (%)
        uint8 magicPowerMulti; // Base magic power effectiveness (%)
    }

    mapping(uint256 => CharacterStats) public characters;
    mapping(CharacterClass => ClassMultipliers) public classMultipliers;
    mapping(CharacterClass => uint16) public classChangeRequirements;

    uint8 public constant STAT_UPGRADE_COST = 1;

    uint256 public constant XP_PER_LEVEL = 100;

    uint8 public constant POINTS_PER_LEVEL = 10;

    uint8 public constant MAX_STAT_VALUE = 255;
    // points constants (1 point = 1%)
    uint16 constant POINTS = 100; //100%
    uint16 constant VETERAN_BONUS = 10; // 10%
    uint16 constant VETERAN_HEALTH_BONUS = 5; // 5%
    uint16 constant VETERAN_DEFENSE_BONU_ = 5; // 5%
    uint16 constant KNIGHT_HEALTH_BONUS = 15; // 15%
    uint16 constant KING_HEALTH_BONUS = 20; // 20%
    uint16 constant GOD_HEALTH_BONUS = 10; // 10%
    uint16 constant KNIGHT_DEFENSE_BONUS = 20; // 20%
    uint16 constant ARCHER_DODGE_BONUS = 30; // 30%
    uint16 constant MAX_DODGE_CHANCE = 40; // 40%
    uint16 constant MAX_CRIT_RATE = 40; // 40%
    uint16 constant BASE_CRIT_RATE = 5; // 5%
    uint16 constant MIN_CRIT_MULTIPLIER = 150; // 150%
    uint16 constant MAX_CRIT_MULTIPLIER = 350; // 350%

    //Base events i dont believe they are that much needed tho
    event CharacterCreated(
        address creator,
        uint256 indexed tokenId,
        string name,
        uint8 strength,
        uint8 defense,
        uint8 agility,
        uint8 vitality,
        uint8 intelligence,
        uint8 magicPower,
        CharacterClass characterClass
    );

    event WeaponEquipped(uint256 indexed characterId, uint256 indexed weaponId);
    event WeaponUnequipped(uint256 indexed characterId, uint256 weaponId);
    event ArmorEquipped(uint256 indexed characterId, uint256 indexed armorId);
    event ArmorUnequipped(uint256 indexed characterId, uint256 armorId);
    event StatsIncreased(
        uint256 indexed characterId,
        uint8 strengthIncrease,
        uint8 defenseIncrease,
        uint8 agilityIncrease,
        uint8 vitalityIncrease,
        uint8 intelligenceIncrease,
        uint8 magicPowerIncrease
    );

    constructor() ERC721("RealmClashCharacters", "RCCC") {
        _allowedMinters[msg.sender] = true;

        // class multipliers
        // Tried to make it overall balanced
        classMultipliers[CharacterClass.Human] = ClassMultipliers(
            80, //strengthMulti
            80, //defenseMulti
            80, //agilityMulti
            80, //vitalityMulti
            80, //intelligenceMulti
            70 //magicPowerMulti
        );
        classMultipliers[CharacterClass.King] = ClassMultipliers(
            100, //strengthMulti
            90, //defenseMulti
            80, //agilityMulti
            100, //vitalityMulti
            70, //intelligenceMulti
            60 //magicPowerMulti
        );
        classMultipliers[CharacterClass.Mage] = ClassMultipliers(
            60, //strengthMulti
            60, //defenseMulti
            80, //agilityMulti
            70, //vitalityMulti
            100, //intelligenceMulti
            110 //magicPowerMulti
        );
        classMultipliers[CharacterClass.Archer] = ClassMultipliers(
            80, //strengthMulti
            70, //defenseMulti
            110, //agilityMulti
            80, //vitalityMulti
            85, //intelligenceMulti
            75 //magicPowerMulti
        );
        classMultipliers[CharacterClass.Knight] = ClassMultipliers(
            100, //strengthMulti
            100, //defenseMulti
            70, //agilityMulti
            90, //vitalityMulti
            60, //intelligenceMulti
            50 //magicPowerMulti
        );
        classMultipliers[CharacterClass.Demon] = ClassMultipliers(
            100, //strengthMulti
            70, //defenseMulti
            80, //agilityMulti
            80, //vitalityMulti
            70, //intelligenceMulti
            100 //magicPowerMulti
        );
        //Typical overpowered class
        classMultipliers[CharacterClass.God] = ClassMultipliers(
            100, //strengthMulti
            100, //defenseMulti
            100, //agilityMulti
            100, //vitalityMulti
            100, //intelligenceMulti
            100 //magicPowerMulti
        );

        // Initialize class change requirements (stat points needed)
        classChangeRequirements[CharacterClass.King] = 80;
        classChangeRequirements[CharacterClass.Mage] = 50;
        classChangeRequirements[CharacterClass.Archer] = 40;
        classChangeRequirements[CharacterClass.Knight] = 60;
        classChangeRequirements[CharacterClass.Demon] = 90;
        classChangeRequirements[CharacterClass.God] = 100;
    }

    modifier onlyMinter() {
        require(
            _allowedMinters[msg.sender] || msg.sender == address(this),
            "Not authorized to mint or Not contract"
        );
        _;
    }

    modifier characterExists(uint256 _tokenId) {
        _;
    }

    modifier onlyOwnerOf(uint256 _tokenId) {
        require(ownerOf(_tokenId) == msg.sender, "Not the character owner");
        _;
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function changeMinterStatus(address _minter) external onlyMinter {
        _allowedMinters[_minter] = !_allowedMinters[_minter];
    }

    function setWeaponContract(address _address) external onlyMinter {
        weaponContractAddress = _address;
    }

    function setArmorContract(address _address) external onlyMinter {
        armorContractAddress = _address;
    }

    function mint(address _to, string memory _uri) internal returns (uint256) {
        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;
        _safeMint(_to, newTokenId);
        _setTokenURI(newTokenId, _uri);
        return newTokenId;
    }

    function setTokenUriBackdoor(
        uint256 _tokenId,
        string memory _uri
    ) external onlyMinter {
        _setTokenURI(_tokenId, _uri);
    }

    function createCharacter(
        string memory _name,
        string memory _uri,
        uint8 _strength,
        uint8 _defense,
        uint8 _agility,
        uint8 _vitality,
        uint8 _intelligence,
        uint8 _magicPower,
        uint8 _classId
    )
        external
        /*onlyMinter*/ characterExists(_tokenIdCounter)
        returns (uint256)
    {
        uint256 _tokenId = mint(msg.sender, _uri);
        require(_exists(_tokenId), "Character does not exist");
        require(_classId <= uint8(CharacterClass.God), "Invalid class ID");

        characters[_tokenId] = CharacterStats({
            id: _tokenId,
            name: _name,
            strength: _strength,
            defense: _defense,
            agility: _agility,
            vitality: _vitality,
            intelligence: _intelligence,
            magicPower: _magicPower,
            wins: 0,
            losses: 0,
            isVeteran: false,
            lastBattleTime: 0,
            characterClass: CharacterClass(_classId),
            weaponId: 0,
            armorId: 0,
            statPoints: 10, // Start with 10 stat points
            experience: 0
        });

        emit CharacterCreated(
            msg.sender,
            _tokenId,
            _name,
            _strength,
            _defense,
            _agility,
            _vitality,
            _intelligence,
            _magicPower,
            CharacterClass(_classId)
        );

        return _tokenId;
    }

    function equipWeapon(
        uint256 _characterId,
        uint256 _weaponId
    ) external onlyOwnerOf(_characterId) {
        require(weaponContractAddress != address(0), "Weapon contract not set");
        require(
            WeaponInterface(weaponContractAddress).ownerOf(_weaponId) ==
                msg.sender,
            "Not the weapon owner"
        );

        characters[_characterId].weaponId = _weaponId;
        emit WeaponEquipped(_characterId, _weaponId);
    }

    function unequipWeapon(
        uint256 _characterId
    ) external onlyOwnerOf(_characterId) {
        uint256 weaponId = characters[_characterId].weaponId;
        characters[_characterId].weaponId = 0;
        emit WeaponUnequipped(_characterId, weaponId);
    }

    function equipArmor(
        uint256 _characterId,
        uint256 _armorId
    ) external onlyOwnerOf(_characterId) {
        require(armorContractAddress != address(0), "Armor contract not set");
        require(
            ArmorInterface(armorContractAddress).ownerOf(_armorId) ==
                msg.sender,
            "Not the armor owner"
        );

        characters[_characterId].armorId = _armorId;
        emit ArmorEquipped(_characterId, _armorId);
    }

    function unequipArmor(
        uint256 _characterId
    ) external onlyOwnerOf(_characterId) {
        uint256 armorId = characters[_characterId].armorId;
        characters[_characterId].armorId = 0;
        emit ArmorUnequipped(_characterId, armorId);
    }

    // Apply diminishing returns formula to a stat value
    function applyDiminishingReturns(
        uint256 statValue,
        uint8 classMultiplier
    ) internal pure returns (uint256) {
        // Base formula: effective = actual * (classMultiplier/100) * (1 - log(statValue)/log(MAX_VALUE*10))
        if (statValue <= 30) {
            // No diminishing returns for low stats
            return (statValue * classMultiplier) / 100;
        } else if (statValue <= 100) {
            // Mild diminishing returns in mid-range
            uint256 diminishFactor = 95 + (5 * (100 - statValue)) / 70; // 95-100%
            return (statValue * classMultiplier * diminishFactor) / 10000;
        } else {
            // Stronger diminishing returns at high values
            uint256 diminishFactor = 70 + (25 * (255 - statValue)) / 155; // 70-95%
            return (statValue * classMultiplier * diminishFactor) / 10000;
        }
    }

    function getEffectiveStrength(
        uint256 _characterId
    ) public view returns (uint256) {
        CharacterStats memory character = characters[_characterId];
        uint8 classMulti = classMultipliers[character.characterClass]
            .strengthMulti;
        return applyDiminishingReturns(character.strength, classMulti);
    }

    function getEffectiveDefense(
        uint256 _characterId
    ) public view returns (uint256) {
        CharacterStats memory character = characters[_characterId];
        uint8 classMulti = classMultipliers[character.characterClass]
            .defenseMulti;
        return applyDiminishingReturns(character.defense, classMulti);
    }

    function getEffectiveAgility(
        uint256 _characterId
    ) public view returns (uint256) {
        CharacterStats memory character = characters[_characterId];
        uint8 classMulti = classMultipliers[character.characterClass]
            .agilityMulti;
        return applyDiminishingReturns(character.agility, classMulti);
    }

    function getEffectiveVitality(
        uint256 _characterId
    ) public view returns (uint256) {
        CharacterStats memory character = characters[_characterId];
        uint8 classMulti = classMultipliers[character.characterClass]
            .vitalityMulti;
        return applyDiminishingReturns(character.vitality, classMulti);
    }

    function getEffectiveIntelligence(
        uint256 _characterId
    ) public view returns (uint256) {
        CharacterStats memory character = characters[_characterId];
        uint8 classMulti = classMultipliers[character.characterClass]
            .intelligenceMulti;
        return applyDiminishingReturns(character.intelligence, classMulti);
    }

    function getEffectiveMagicPower(
        uint256 _characterId
    ) public view returns (uint256) {
        CharacterStats memory character = characters[_characterId];
        uint8 classMulti = classMultipliers[character.characterClass]
            .magicPowerMulti;
        return applyDiminishingReturns(character.magicPower, classMulti);
    }

    function calculateDamage(
        uint256 _characterId
    ) public view returns (uint256, bool, uint256) {
        require(_exists(_characterId), "Character does not exist");

        CharacterStats memory character = characters[_characterId];

        uint256 effectiveStrength = getEffectiveStrength(_characterId);
        uint256 effectiveAgility = getEffectiveAgility(_characterId);
        uint256 effectiveIntelligence = getEffectiveIntelligence(_characterId);
        uint256 effectiveMagicPower = getEffectiveMagicPower(_characterId);

        uint256 physicalDamage = effectiveStrength * 6;

        uint256 magicalDamage = effectiveMagicPower * 5;

        uint256 baseDamage;
        if (character.characterClass == CharacterClass.Mage) {
            // Mages primarily use magic damage
            baseDamage =
                ((magicalDamage * 80) / 100) +
                ((physicalDamage * 20) / 100);
        } else if (character.characterClass == CharacterClass.Demon) {
            // Demons use a mix of physical and magical damage
            baseDamage =
                ((magicalDamage * 40) / 100) +
                ((physicalDamage * 60) / 100);
        } else if (character.characterClass == CharacterClass.God) {
            // Gods use the best of both
            baseDamage = magicalDamage > physicalDamage
                ? magicalDamage
                : physicalDamage;
            baseDamage += (magicalDamage + physicalDamage) / 10; // 10% bonus from the lesser stat
        } else {
            // Other classes primarily use physical damage
            baseDamage =
                ((physicalDamage * 80) / 100) +
                ((magicalDamage * 20) / 100);
        }

        // Intelligence adds efficiency to all damage types
        uint256 intBonus = effectiveIntelligence * 2;

        // Agility adds attack speed bonus
        uint256 agilityBonus = effectiveAgility *
            (character.characterClass == CharacterClass.Archer ? 2 : 1);

        uint256 totalDamage = baseDamage + intBonus + agilityBonus;

        // Equipment bonuses
        if (character.weaponId > 0 && weaponContractAddress != address(0)) {
            WeaponInterface.WeaponStats memory weapon = WeaponInterface(
                weaponContractAddress
            ).getWeaponStats(character.weaponId);

            totalDamage += weapon.damageBonus * 3;

            // Class-specific weapon bonuses
            if (character.characterClass == CharacterClass.Mage) {
                totalDamage += weapon.magicPowerBonus * 3;
                totalDamage += weapon.intelligenceBonus * 2;
            } else if (character.characterClass == CharacterClass.Archer) {
                totalDamage += weapon.agilityBonus * 3;
                totalDamage += (weapon.damageBonus * 3) / 2;
            } else {
                totalDamage += (weapon.damageBonus * 3) / 2;
                totalDamage += weapon.intelligenceBonus * 1;
                totalDamage += weapon.magicPowerBonus * 1;
            }
        }

        if (character.armorId > 0 && armorContractAddress != address(0)) {
            ArmorInterface.ArmorStats memory armor = ArmorInterface(
                armorContractAddress
            ).getArmorStats(character.armorId);
            totalDamage += armor.damageBonus * 1;

            if (character.characterClass == CharacterClass.Mage) {
                totalDamage += armor.magicPowerBonus * 2;
            }
        }

        // Veteran bonus
        if (character.isVeteran) {
            totalDamage += totalDamage / 10; // 10% bonus for veterans
        }

        // Critical hit calculation based on intelligence
        uint256 critRate = BASE_CRIT_RATE + (effectiveIntelligence / 4); // Base 5% + 0.25% per effective intelligence
        if (critRate > MAX_CRIT_RATE) {
            critRate = MAX_CRIT_RATE; // Cap crit rate at 40%
        }

        uint256 critMultiplier = MIN_CRIT_MULTIPLIER;

        if (character.characterClass == CharacterClass.Mage) {
            critMultiplier += (effectiveIntelligence * 3) / 2; // Mages get x1.5 crit bonus
        } else if (character.characterClass == CharacterClass.Archer) {
            critMultiplier += effectiveIntelligence + (effectiveAgility / 2);
        } else {
            critMultiplier += effectiveIntelligence;
        }

        if (critMultiplier > MAX_CRIT_MULTIPLIER) {
            critMultiplier = MAX_CRIT_MULTIPLIER;
        }

        // Determine if this attack is a critical hit
        bool isCritical = _pseudoRandomNumber(_characterId) <= critRate;

        // Apply critical multiplier if critical hit
        if (isCritical) {
            totalDamage = (totalDamage * critMultiplier) / 100;
        }

        return (totalDamage, isCritical, critMultiplier);
    }

    function calculateHealth(
        uint256 _characterId
    ) public view returns (uint256) {
        require(_exists(_characterId), "Character does not exist");

        CharacterStats memory character = characters[_characterId];

        // Get effective stats with class multipliers and diminishing returns
        uint256 effectiveVitality = getEffectiveVitality(_characterId);
        uint256 effectiveStrength = getEffectiveStrength(_characterId);
        uint256 effectiveMagicPower = getEffectiveMagicPower(_characterId);
        uint256 effectiveIntelligence = getEffectiveIntelligence(_characterId);

        uint256 baseHealth = effectiveVitality * 20;

        uint256 strengthBonus = effectiveStrength * 7;

        uint256 magicPowerBonus = (effectiveMagicPower * 7) +
            (effectiveIntelligence * 3);

        uint256 totalHealth = baseHealth + strengthBonus + magicPowerBonus;

        if (character.characterClass == CharacterClass.Knight) {
            totalHealth = (totalHealth * (100 + KNIGHT_HEALTH_BONUS)) / 100; // 15% bonus for Knights
        } else if (character.characterClass == CharacterClass.King) {
            totalHealth = (totalHealth * (100 + KING_HEALTH_BONUS)) / 100; // 20% bonus for Kings
        } else if (character.characterClass == CharacterClass.God) {
            totalHealth = (totalHealth * (100 + GOD_HEALTH_BONUS)) / 100; // 10% bonus for Gods
        }

        if (character.armorId > 0 && armorContractAddress != address(0)) {
            ArmorInterface.ArmorStats memory armor = ArmorInterface(
                armorContractAddress
            ).getArmorStats(character.armorId);
            totalHealth += armor.vitalityBonus * 15;
            totalHealth += armor.defenseBonus * 5;
            totalHealth += armor.magicPowerBonus * 3;
        }

        if (character.weaponId > 0 && weaponContractAddress != address(0)) {
            WeaponInterface.WeaponStats memory weapon = WeaponInterface(
                weaponContractAddress
            ).getWeaponStats(character.weaponId);
            totalHealth += weapon.vitalityBonus * 8;
            totalHealth += weapon.magicPowerBonus * 2;
        }

        if (character.isVeteran) {
            totalHealth += (totalHealth * VETERAN_HEALTH_BONUS) / 100; // 5% bonus for veterans
        }

        return totalHealth;
    }

    function calculateDefense(
        uint256 _characterId
    ) public view returns (uint256) {
        require(_exists(_characterId), "Character does not exist");

        CharacterStats memory character = characters[_characterId];

        uint256 effectiveDefense = getEffectiveDefense(_characterId);
        uint256 effectiveAgility = getEffectiveAgility(_characterId);
        uint256 effectiveIntelligence = getEffectiveIntelligence(_characterId);
        uint256 effectiveMagicPower = getEffectiveMagicPower(_characterId);

        uint256 baseDefense = effectiveDefense * 4;

        uint256 agilityBonus = effectiveAgility * 2;
        uint256 intelligenceBonus = (effectiveIntelligence * 3) / 2;
        uint256 magicPowerBonus = (effectiveMagicPower * 3) / 2;

        uint256 totalDefense = baseDefense +
            agilityBonus +
            intelligenceBonus +
            magicPowerBonus;

        if (character.characterClass == CharacterClass.Knight) {
            totalDefense = (totalDefense * (100 + KNIGHT_DEFENSE_BONUS)) / 100; // 20% bonus for Knights
        } else if (character.characterClass == CharacterClass.Archer) {
            totalDefense =
                baseDefense +
                ((agilityBonus * 3) / 2) +
                intelligenceBonus +
                magicPowerBonus;
        } else if (character.characterClass == CharacterClass.Mage) {
            totalDefense =
                baseDefense +
                agilityBonus +
                ((intelligenceBonus * 3) / 2) +
                ((magicPowerBonus * 3) / 2);
        }

        if (character.armorId > 0 && armorContractAddress != address(0)) {
            ArmorInterface.ArmorStats memory armor = ArmorInterface(
                armorContractAddress
            ).getArmorStats(character.armorId);
            totalDefense += armor.defenseBonus * 4;
            totalDefense += armor.agilityBonus * 2;
            totalDefense += armor.intelligenceBonus * 2;
            totalDefense += armor.magicPowerBonus * 2;
        }

        if (character.weaponId > 0 && weaponContractAddress != address(0)) {
            WeaponInterface.WeaponStats memory weapon = WeaponInterface(
                weaponContractAddress
            ).getWeaponStats(character.weaponId);
            totalDefense += weapon.defenseBonus * 2;
            totalDefense += weapon.intelligenceBonus;
            totalDefense += weapon.magicPowerBonus;
        }

        // Veteran bonus
        if (character.isVeteran) {
            totalDefense += (totalDefense * VETERAN_DEFENSE_BONU_) / 100; // 5% bonus for veterans
        }

        return totalDefense;
    }

    // Calculate dodge chance based on agility
    function calculateDodgeChance(
        uint256 _characterId
    ) public view returns (uint256) {
        uint256 effectiveAgility = getEffectiveAgility(_characterId);
        CharacterStats memory character = characters[_characterId];

        // Base dodge chance
        uint256 dodgeChance = effectiveAgility / 5; // 0.2% per agility point

        // Class bonuses
        if (character.characterClass == CharacterClass.Archer) {
            dodgeChance = (dodgeChance * (100 + ARCHER_DODGE_BONUS)) / 100; // 30% bonus for Archers
        }

        // Equipment bonus
        if (character.armorId > 0 && armorContractAddress != address(0)) {
            ArmorInterface.ArmorStats memory armor = ArmorInterface(
                armorContractAddress
            ).getArmorStats(character.armorId);
            dodgeChance += armor.agilityBonus / 4;
        }

        // Cap at 40%
        if (dodgeChance > MAX_DODGE_CHANCE) {
            dodgeChance = MAX_DODGE_CHANCE;
        }

        return dodgeChance;
    }

    // Add experience to a character
    function addExperience(
        uint256 _characterId,
        uint256 _experience
    ) public onlyMinter characterExists(_characterId) {
        uint256 oldLevel = characters[_characterId].experience / XP_PER_LEVEL;
        characters[_characterId].experience += _experience;
        uint256 newLevel = characters[_characterId].experience / XP_PER_LEVEL;

        // If leveled up, award stat points
        if (newLevel > oldLevel) {
            uint256 levelsGained = newLevel - oldLevel;
            characters[_characterId].statPoints += uint16(
                levelsGained * POINTS_PER_LEVEL
            );
        }
    }

    // Update character after battle
    function updateBattleResult(
        uint256 _characterId,
        bool _isWinner,
        uint256 _experienceGained
    ) external onlyMinter characterExists(_characterId) {
        if (_isWinner) {
            characters[_characterId].wins++;
            addExperience(_characterId, _experienceGained);
        } else {
            characters[_characterId].losses++;
            // Give some experience even for losses
            addExperience(_characterId, _experienceGained / 4);
        }

        characters[_characterId].lastBattleTime = block.timestamp;

        if (characters[_characterId].wins >= 10) {
            characters[_characterId].isVeteran = true;
        }
    }

    // Use stat points to increase a stat
    function increaseStats(
        uint256 _characterId,
        uint8 _strengthIncrease,
        uint8 _defenseIncrease,
        uint8 _agilityIncrease,
        uint8 _vitalityIncrease,
        uint8 _intelligenceIncrease,
        uint8 _magicPowerIncrease
    ) external onlyOwnerOf(_characterId) {
        CharacterStats storage character = characters[_characterId];

        // Calculate total points needed
        uint16 totalPointsNeeded = _strengthIncrease +
            _defenseIncrease +
            _agilityIncrease +
            _vitalityIncrease +
            _intelligenceIncrease +
            _magicPowerIncrease;

        require(
            character.statPoints >= totalPointsNeeded,
            "Not enough stat points"
        );

        // Ensure stats don't exceed maximum
        require(
            character.strength + _strengthIncrease <= MAX_STAT_VALUE &&
                character.defense + _defenseIncrease <= MAX_STAT_VALUE &&
                character.agility + _agilityIncrease <= MAX_STAT_VALUE &&
                character.vitality + _vitalityIncrease <= MAX_STAT_VALUE &&
                character.intelligence + _intelligenceIncrease <=
                MAX_STAT_VALUE &&
                character.magicPower + _magicPowerIncrease <= MAX_STAT_VALUE,
            "Stats would exceed maximum"
        );

        // Apply the increases
        character.strength += _strengthIncrease;
        character.defense += _defenseIncrease;
        character.agility += _agilityIncrease;
        character.vitality += _vitalityIncrease;
        character.intelligence += _intelligenceIncrease;
        character.magicPower += _magicPowerIncrease;

        // Deduct the points
        character.statPoints -= totalPointsNeeded;

        emit StatsIncreased(
            _characterId,
            _strengthIncrease,
            _defenseIncrease,
            _agilityIncrease,
            _vitalityIncrease,
            _intelligenceIncrease,
            _magicPowerIncrease
        );
    }

    // Change character class
    function changeClass(
        uint256 _characterId,
        uint8 _newClassId
    ) external onlyOwnerOf(_characterId) {
        require(_newClassId <= uint8(CharacterClass.God), "Invalid class ID");

        CharacterStats storage character = characters[_characterId];
        CharacterClass newClass = CharacterClass(_newClassId);

        // Can't change to the same class
        require(character.characterClass != newClass, "Already this class");

        // Only Humans can change class
        require(
            character.characterClass == CharacterClass.Human,
            "Only Humans can change class"
        );

        // Check if enough stat points
        uint16 requiredPoints = classChangeRequirements[newClass];
        require(
            character.statPoints >= requiredPoints,
            "Not enough stat points"
        );

        // Deduct stat points
        character.statPoints -= requiredPoints;

        // Change class
        character.characterClass = newClass;

        // Give class-specific bonuses
        if (newClass == CharacterClass.Mage) {
            character.intelligence += 10;
            character.magicPower += 15;
        } else if (newClass == CharacterClass.Knight) {
            character.strength += 10;
            character.defense += 15;
        } else if (newClass == CharacterClass.Archer) {
            character.agility += 15;
            character.intelligence += 5;
        } else if (newClass == CharacterClass.King) {
            character.strength += 10;
            character.vitality += 10;
            character.defense += 5;
        } else if (newClass == CharacterClass.Demon) {
            character.strength += 15;
            character.magicPower += 10;
        } else if (newClass == CharacterClass.God) {
            character.strength += 5;
            character.defense += 5;
            character.vitality += 5;
            character.agility += 5;
            character.intelligence += 5;
            character.magicPower += 5;
        }
    }

    // Simple pseudo-random number generator for crit calculation
    function _pseudoRandomNumber(uint256 seed) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        blockhash(block.number - 1),
                        seed,
                        block.timestamp
                    )
                )
            ) % 100;
    }

    function getCharacterStats(
        uint256 _tokenId
    ) external view returns (CharacterStats memory) {
        require(_exists(_tokenId), "Character does not exist");
        return characters[_tokenId];
    }

    function getCharactersByOwner(
        address _owner
    ) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokenIds;
    }

    function burn(uint256 _tokenId) external onlyOwnerOf(_tokenId) {
        _burn(_tokenId);
        delete characters[_tokenId];
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

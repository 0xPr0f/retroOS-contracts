// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {CharacterCard} from "../../../src/RealmClash/ClashBattle/CharacterCard.sol";

contract CharacterCardTest is Test {
    CharacterCard public characterCard;

    function setUp() public {
        characterCard = new CharacterCard();
    }

    function test_CreateCharacterNotMinter() public {
        // Should not revert as i have disabled only minter can create character
        // vm.expectRevert("Not authorized to mint");
        characterCard.createCharacter("Alice", "uri", 50, 50, 50, 50, 50, 50, 2);
    }

    function test_changeMinterStatus() public {
        characterCard.changeMinterStatus(address(this));
        characterCard.createCharacter("Alice", "uri", 50, 50, 50, 50, 50, 50, 2);
        assertEq(characterCard.balanceOf(address(this)), 1);
    }

    function test_SetWeaponContract() public {
        characterCard.setWeaponContract(address(0x123));
        assertEq(characterCard.weaponContractAddress(), address(0x123));
    }

    function test_SetArmorContract() public {
        characterCard.setArmorContract(address(0x456));
        assertEq(characterCard.armorContractAddress(), address(0x456));
    }

    function test_Revert_EquipWeaponNotOwner() public {
        uint256 characterId = createTestCharacter();
        vm.expectRevert();
        characterCard.equipWeapon(characterId, 1);
    }

    function test_Revert_EquipArmorNotOwner() public {
        uint256 characterId = createTestCharacter();
        vm.expectRevert();
        characterCard.equipArmor(characterId, 1);
    }

    function test_Revert_IncreaseStatsNotOwner() public {
        uint256 characterId = createTestCharacter();
        vm.prank(address(135));
        vm.expectRevert("Not the character owner");
        characterCard.increaseStats(characterId, 1, 1, 1, 1, 1, 1);
    }

    function test_GetCharacterStats() public {
        uint256 characterId = createTestCharacter();
        CharacterCard.CharacterStats memory stats = characterCard.getCharacterStats(characterId);
        assertEq(stats.name, "Alice");
        assertEq(stats.strength, 50);
    }

    function test_GetCharactersByOwner() public {
        characterCard.changeMinterStatus(address(this));
        createTestCharacter();
        createTestCharacter();
        uint256[] memory characters = characterCard.getCharactersByOwner(address(this));
        assertEq(characters.length, 2);
    }

    function test_BurnNotMinter() public {
        vm.startPrank(address(135));
        uint256 characterId = createTestCharacter();
        characterCard.burn(characterId);
        vm.stopPrank();
    }

    function createTestCharacter() private returns (uint256) {
        characterCard.createCharacter("Alice", "uri", 50, 50, 50, 50, 50, 50, 3);
        return 1;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

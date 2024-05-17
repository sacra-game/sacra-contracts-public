// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IGOC.sol";
import "../interfaces/IStoryController.sol";
import "./CalcLib.sol";
import "./PackingLib.sol";

library GOCLib {
  using EnumerableSet for EnumerableSet.UintSet;
  using PackingLib for address;

  /// @param cTypes Array of object subtypes, see IGOC.ObjectSubType.XXX
  /// @param chances Chances in range 0-1e9, chances are corresponded to {cTypes} array
  function getRandomObject(
    IGOC.MainState storage s,
    IStoryController sc,
    uint8[] memory cTypes,
    uint32[] memory chances,
    uint8 biome,
    address heroToken,
    uint heroTokenId
  ) internal returns (uint32 objectId) {

    uint8 cType = _getObjectType(cTypes, chances, CalcLib.pseudoRandom);

    EnumerableSet.UintSet storage objects = s.objectIds[packObjectMeta(biome, cType)];
    uint len = objects.length();
    if (len == 0) revert IAppErrors.EmptyObjects();
    uint objectArrayIdx = len == 1
      ? 0
      : CalcLib.pseudoRandom(len - 1);

    EnumerableSet.UintSet storage played = s.playedObjects[heroToken.packPlayedObjKey(uint64(heroTokenId), cType, biome)];
    objectId = _searchObject(sc, len, objects, played, objectArrayIdx, false, heroToken, heroTokenId, cType);

    if (objectId == 0) revert IAppErrors.ObjectNotFound();
    played.add(objectId);
  }

  /// @notice Select cType using pseudo-random value according to the given {chances}
  /// @param cTypes Zero values are ignored.
  /// @param chances [0..100], decimals 9. At least once item should have value 100 to avoid {UnknownObjectType} error.
  /// @param random_ CalcLib.pseudoRandom, required for unit tests
  function _getObjectType(
    uint8[] memory cTypes,
    uint32[] memory chances,
    function (uint) internal view returns (uint) random_
  ) internal view returns (uint8 cType) {
    uint len = cTypes.length;
    if (len == 0 || len != chances.length) revert IAppErrors.WrongGetObjectTypeInput();

    if (len == 1) {
      cType = cTypes[0];
    } else {
      uint random = random_(CalcLib.MAX_CHANCE);
      uint minChance = CalcLib.MAX_CHANCE + 1;
      for (uint i; i < len; ++i) {
        // obj set can contain empty values, ignore them
        if (cTypes[i] == 0) continue;
        if (chances[i] > CalcLib.MAX_CHANCE) revert IAppErrors.WrongChances(chances[i], CalcLib.MAX_CHANCE);
        if ((CalcLib.MAX_CHANCE - chances[i]) <= random) {
          if (chances[i] < minChance) {
            minChance = chances[i];
            cType = cTypes[i];
          }
        }
      }
    }

    if (cType == 0) revert IAppErrors.UnknownObjectTypeGoc1(0);
    return cType;
  }

  /// @notice Find first object in {objects} available for the hero starting from {objArrayIdx}
  /// If object not found clear {played} and try to search again.
  /// @param lenObjects Length of {objects}
  /// @param objArrayIdx Start index in objects
  /// @param cType Object subtype
  /// @param skipPlayed true - don't check if the found object was already played
  /// @return objectId ID of the found object or 0 if the object is not found
  function _searchObject(
    IStoryController sc,
    uint lenObjects,
    EnumerableSet.UintSet storage objects,
    EnumerableSet.UintSet storage played,
    uint objArrayIdx,
    bool skipPlayed,
    address heroToken,
    uint heroTokenId,
    uint8 cType
  ) internal returns (uint32 objectId) {

    // clear played objects if we played them all at the current biome
    if (played.length() >= lenObjects) {
      skipPlayed = true;
      _clearPlayedObjects(played);
    }

    bool foundValid;

    unchecked {
    // search in a loop available objects
      for (uint i; i < lenObjects; ++i) {
        if (objArrayIdx >= lenObjects) {
          objArrayIdx = 0;
        }
        uint32 objId = uint32(objects.at(objArrayIdx));
        if (
          isAvailableForHero(sc, objId, cType, heroToken, heroTokenId)
          && (skipPlayed || !played.contains(objId))
        ) {
          foundValid = true;
          objectId = objId;
          break;
        }

        ++objArrayIdx;
      }
    }
    // in case when we do not have available objects it is possible they are not eligible and need to reset counter
    if (!foundValid && !skipPlayed) {
      _clearPlayedObjects(played);
      objectId = _searchObject(sc, lenObjects, objects, played, objArrayIdx, true, heroToken, heroTokenId, cType);
    }

    return objectId;
  }

  function _clearPlayedObjects(EnumerableSet.UintSet storage played) internal {
    uint[] memory values = played.values();
    for (uint i; i < values.length; ++i) {
      played.remove(values[i]);
    }
  }

  /// @notice Check if the object subtype is available for the hero
  function isAvailableForHero(IStoryController sc, uint32 objId, uint8 objectSubType, address hero, uint heroId) internal view returns (bool) {
    IGOC.ObjectType objType = getObjectTypeBySubType(IGOC.ObjectSubType(objectSubType));
    if (objType == IGOC.ObjectType.EVENT) {
      // no checks
      return true;
    } else if (objType == IGOC.ObjectType.MONSTER) {
      // no checks
      return true;
    } else if (objType == IGOC.ObjectType.STORY) {
      return sc.isStoryAvailableForHero(objId, hero, heroId);
    } else {
      // actually, this case is impossible, getObjectTypeBySubType will revert above if objectSubType is incorrect
      revert IAppErrors.UnknownObjectTypeForSubtype(objectSubType);
    }
  }

  function packObjectMeta(uint8 biome, uint8 oType) internal pure returns (bytes32) {
    return PackingLib.packUint8Array3(biome, oType, 0);
  }

  function unpackObjectMeta(bytes32 data) internal pure returns (uint8 biome, uint8 oType) {
    (biome, oType,) = PackingLib.unpackUint8Array3(data);
  }

  /// @notice Get object type for the given {subType}
  function getObjectTypeBySubType(IGOC.ObjectSubType subType) internal pure returns (IGOC.ObjectType) {
    if (
      subType == IGOC.ObjectSubType.SHRINE_4
      || subType == IGOC.ObjectSubType.CHEST_5
      || subType == IGOC.ObjectSubType.SHRINE_UNIQUE_8
    ) {
      return IGOC.ObjectType.EVENT;
    } else if (
      subType == IGOC.ObjectSubType.ENEMY_NPC_1
      || subType == IGOC.ObjectSubType.ENEMY_NPC_SUPER_RARE_2
      || subType == IGOC.ObjectSubType.BOSS_3
      || subType == IGOC.ObjectSubType.ENEMY_NPC_UNIQUE_10
      || subType == IGOC.ObjectSubType.ENEMY_NPC_INSIDE_32
      || subType == IGOC.ObjectSubType.ENEMY_NPC_INSIDE_RARE_33
      || subType == IGOC.ObjectSubType.ENEMY_NPC_OUTSIDE_34
      || subType == IGOC.ObjectSubType.ENEMY_NPC_OUTSIDE_RARE_35
    ) {
      return IGOC.ObjectType.MONSTER;
    } else if (
      subType == IGOC.ObjectSubType.STORY_6
      || subType == IGOC.ObjectSubType.STORY_UNIQUE_7
      || subType == IGOC.ObjectSubType.STORY_ON_ROAD_11
      || subType == IGOC.ObjectSubType.STORY_UNDERGROUND_12
      || subType == IGOC.ObjectSubType.STORY_NIGHT_CAMP_13
      || subType == IGOC.ObjectSubType.STORY_MOUNTAIN_14
      || subType == IGOC.ObjectSubType.STORY_WATER_15
      || subType == IGOC.ObjectSubType.STORY_CASTLE_16
      || subType == IGOC.ObjectSubType.STORY_HELL_17
      || subType == IGOC.ObjectSubType.STORY_SPACE_18
      || subType == IGOC.ObjectSubType.STORY_WOOD_19
      || subType == IGOC.ObjectSubType.STORY_CATACOMBS_20
      || subType == IGOC.ObjectSubType.STORY_BAD_HOUSE_21
      || subType == IGOC.ObjectSubType.STORY_GOOD_TOWN_22
      || subType == IGOC.ObjectSubType.STORY_BAD_TOWN_23
      || subType == IGOC.ObjectSubType.STORY_BANDIT_CAMP_24
      || subType == IGOC.ObjectSubType.STORY_BEAST_LAIR_25
      || subType == IGOC.ObjectSubType.STORY_PRISON_26
      || subType == IGOC.ObjectSubType.STORY_SWAMP_27
      || subType == IGOC.ObjectSubType.STORY_INSIDE_28
      || subType == IGOC.ObjectSubType.STORY_OUTSIDE_29
      || subType == IGOC.ObjectSubType.STORY_INSIDE_RARE_30
      || subType == IGOC.ObjectSubType.STORY_OUTSIDE_RARE_31
    ) {
      return IGOC.ObjectType.STORY;
    } else {
      revert IAppErrors.UnknownObjectTypeGoc2(uint8(subType));
    }
  }
}

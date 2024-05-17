// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "../interfaces/IGOC.sol";
import "../interfaces/IStatController.sol";
import "../interfaces/IItemController.sol";
import "./IController.sol";
import "./IOracle.sol";
import "./IHeroController.sol";
import "../openzeppelin/EnumerableSet.sol";

interface IStoryController {

  enum AnswerResultId {
    UNKNOWN, // 0
    SUCCESS, // 1
    ATTRIBUTE_FAIL, // 2
    RANDOM_FAIL, // 3
    DELAY_FAIL, // 4
    HERO_CUSTOM_DATA_FAIL, // 5
    GLOBAL_CUSTOM_DATA_FAIL, // 6

    END_SLOT
  }

  enum CustomDataResult {
    UNKNOWN, // 0
    HERO_SUCCESS, // 1
    HERO_FAIL, // 2
    GLOBAL_SUCCESS, // 3
    GLOBAL_FAIL, // 4

    END_SLOT
  }

  /// @custom:storage-location erc7201:story.controller.main
  struct MainState {

    // --- STORY REG INFO ---

    /// @dev Uniq story identification.
    mapping(uint32 => uint16) storyIds;
    /// @dev Revers mapping for stories for using in the next object rewrite logic.
    mapping(uint16 => uint32) idToStory;
    /// @dev Store used ids for stories.
    mapping(uint16 => bool) _usedStoryIds;
    /// @dev Prevent register the story twice
    mapping(uint32 => bool) registeredStories;

    // --- ANSWER MAPPING ---

    /// @dev storyId => all story pages. We need to have this mapping for properly remove meta info
    mapping(uint16 => EnumerableSet.UintSet) allStoryPages;

    /// @dev storyId => all possible answers. We need to have this mapping for properly remove meta info
    mapping(uint16 => EnumerableSet.Bytes32Set) allStoryAnswers;

    /// @dev storyId + pageId + heroClass (zero is default answers) => storyId + pageId + heroClass (zero is default answers) + answerId
    mapping(bytes32 => bytes32[]) answers;
    /// @dev answerUnPackedId + answerResultId => nextPageIds (will be chosen randomly from this array)
    ///      where answerResultId is:
    ///      0 - unknown,
    ///      1 - success,
    ///      2 - attr fail
    ///      3 - random fail
    ///      4 - delay fail
    ///      5 - hero custom data fail
    ///      6 - global custom data fail
    ///      see COUNT_ANSWER_RESULT_IDS
    mapping(bytes32 => uint16[]) nextPageIds;
    /// @dev story + pageId + heroClass (zero is default answers) => random nextObjs (adr + id, like packed nft id)
    mapping(bytes32 => uint32[]) nextObjectsRewrite;

    /// @dev answerPackedId => packed array of uint32[]
    ///      0 - random requirement(uint32, 1 - 99% success of this action, zero means no check)
    ///      1 - delay requirement(uint32, if time since the last call more than this value the check is fail, zero means no check)
    ///      2 - isFinalAnswer(uint8)
    mapping(bytes32 => bytes32) answerAttributes;

    // --- ANSWER REQUIREMENTS ---

    /// @dev answerPackedId => array of AttributeRequirementsPacked
    mapping(bytes32 => bytes32[]) attributeRequirements;
    /// @dev answerPackedId=> array of ItemRequirementsPacked
    mapping(bytes32 => bytes32[]) itemRequirements;
    /// @dev answerPackedId => array of TokenRequirementsPacked
    mapping(bytes32 => bytes32[]) tokenRequirements;
    /// @dev answerPackedId => custom data for hero
    mapping(bytes32 => CustomDataRequirementPacked[]) heroCustomDataRequirement;
    /// @dev answerPackedId => global custom data
    mapping(bytes32 => CustomDataRequirementPacked[]) globalCustomDataRequirement;

    // --- ANSWER RESULTS ---

    /// @dev answerPackedId => change attributes
    mapping(bytes32 => bytes32[]) successInfoAttributes;
    /// @dev answerPackedId => change stats
    mapping(bytes32 => bytes32) successInfoStats;
    /// @dev answerPackedId => mint items
    mapping(bytes32 => bytes32[]) successInfoMintItems;

    /// @dev answerPackedId => change attributes
    mapping(bytes32 => bytes32[]) failInfoAttributes;
    /// @dev answerPackedId => change stats
    mapping(bytes32 => bytes32) failInfoStats;
    /// @dev answerPackedId => mint items
    mapping(bytes32 => bytes32[]) failInfoMintItems;

    /// @dev answerUnPackedId + CustomDataResult => custom data array change
    ///      where CustomDataResult is
    ///      1 - hero success
    ///      2 - hero fail
    ///      3 - global success
    ///      4 - global fail
    ///      see COUNT_CUSTOM_DATA_RESULT_IDS
    mapping(bytes32 => bytes32[]) customDataResult;
    /// @dev answerPackedId => slot+chance+stopIfBurnt
    mapping(bytes32 => bytes32[]) burnItem;

    // --- GENERAL STORY REQUIREMENTS ---

    /// @dev story => Custom hero data requirements for a story. If exist and hero is not eligible should be not chose in a dungeon.
    mapping(uint => CustomDataRequirementRangePacked[]) storyRequiredHeroData;
    /// @dev story => Minimal level for the history. 0 means no requirements.
    mapping(uint => uint) storyRequiredLevel;

    // --- HERO STATES ---

    /// @dev hero + heroId + storyId => pageId + heroLastActionTS
    mapping(bytes32 => bytes32) heroState;

    // --- OTHER ---

    /// @dev storyId => build hash for the last update
    mapping(uint16 => uint) storyBuildHash;
  }

  /// @dev We need to have flat structure coz Solidity can not handle arrays of structs properly
  struct StoryMetaInfo {
    uint16 storyId;

    // --- story reqs

    bytes32[] requiredCustomDataIndex;
    uint64[] requiredCustomDataMinValue;
    uint64[] requiredCustomDataMaxValue;
    bool[] requiredCustomDataIsHero;
    uint minLevel;

    // --- answer reqs

    AnswersMeta answersMeta;
    AnswerNextPageMeta answerNextPage;
    AnswerAttributeRequirementsMeta answerAttributeRequirements;
    AnswerItemRequirementsMeta answerItemRequirements;
    AnswerTokenRequirementsMeta answerTokenRequirements;
    AnswerAttributesMeta answerAttributes;
    AnswerCustomDataMeta answerHeroCustomDataRequirement;
    AnswerCustomDataMeta answerGlobalCustomDataRequirement;

    // --- answer results

    AnswerBurnRandomItemMeta answerBurnRandomItemMeta;
    NextObjRewriteMeta nextObjRewriteMeta;

    // --- story results

    AnswerResultMeta successInfo;
    AnswerResultMeta failInfo;

    AnswerCustomDataResultMeta successHeroCustomData;
    AnswerCustomDataResultMeta failHeroCustomData;
    AnswerCustomDataResultMeta successGlobalCustomData;
    AnswerCustomDataResultMeta failGlobalCustomData;
  }

  struct NextObjRewriteMeta {
    uint16[] nextObjPageIds;
    uint8[] nextObjHeroClasses;
    uint32[][] nextObjIds;
  }

  struct AnswersMeta {
    uint16[] answerPageIds;
    uint8[] answerHeroClasses;
    uint16[] answerIds;
  }

  struct AnswerNextPageMeta {
    uint16[] pageId;
    uint8[] heroClass;
    uint16[] answerId;
    uint8[] answerResultIds;
    uint16[][] answerNextPageIds;
  }

  struct AnswerAttributeRequirementsMeta {
    uint16[] pageId;
    uint8[] heroClass;
    uint16[] answerId;
    bool[][] cores;
    uint8[][] ids;
    int32[][] values;
  }

  struct AnswerItemRequirementsMeta {
    uint16[] pageId;
    uint8[] heroClass;
    uint16[] answerId;
    address[][] requireItems;
    bool[][] requireItemBurn;
    bool[][] requireItemEquipped;
  }

  struct AnswerTokenRequirementsMeta {
    uint16[] pageId;
    uint8[] heroClass;
    uint16[] answerId;
    address[][] requireToken;
    uint88[][] requireAmount;
    bool[][] requireTransfer;
  }

  struct AnswerAttributesMeta {
    uint16[] pageId;
    uint8[] heroClass;
    uint16[] answerId;
    uint32[] randomRequirements;
    uint32[] delayRequirements;
    bool[] isFinalAnswer;
  }

  struct AnswerCustomDataMeta {
    uint16[] pageId;
    uint8[] heroClass;
    uint16[] answerId;

    bytes32[][] dataIndexes;
    bool[][] mandatory;
    uint64[][] dataValuesMin;
    uint64[][] dataValuesMax;
  }

  struct AnswerResultMeta {
    uint16[] pageId;
    uint8[] heroClass;
    uint16[] answerId;

    uint8[][] attributeIds;
    /// @dev Max value is limitied by int24, see toBytes32ArrayWithIds impl
    int32[][] attributeValues;

    uint32[] experience;
    int32[] heal;
    int32[] manaRegen;
    int32[] lifeChancesRecovered;
    int32[] damage;
    int32[] manaConsumed;

    address[][] mintItems;
    uint32[][] mintItemsChances;
  }

  struct AnswerCustomDataResultMeta {
    uint16[] pageId;
    uint8[] heroClass;
    uint16[] answerId;

    bytes32[][] dataIndexes;
    int16[][] dataValues;
  }

  struct AnswerBurnRandomItemMeta {
    uint16[] pageId;
    uint8[] heroClass;
    uint16[] answerId;

    /// @notice 0 - random slot
    uint8[][] slots;
    /// @notice typical chances are [0..100] (no decimals here)
    uint64[][] chances;
    bool[][] isStopIfBurnt;
  }

  struct CustomDataRequirementPacked {
    bytes32 index;
    /// @dev min(uint64) + max(uint64) + mandatory(uint8)
    bytes32 data;
  }

  struct CustomDataRequirementRangePacked {
    bytes32 index;
    /// @dev min(uint64) + max(uint64) + isHeroData(uint8)
    bytes32 data;
  }

  struct StatsChange {
    uint32 experience;
    int32 heal;
    int32 manaRegen;
    int32 lifeChancesRecovered;
    int32 damage;
    int32 manaConsumed;
  }

  struct StoryActionContext {
    uint stageId;
    uint iteration;
    bytes32 answerIdHash;
    bytes32 answerAttributes;
    address sender;
    address heroToken;
    IController controller;
    IStatController statController;
    IHeroController heroController;
    IOracle oracle;
    IItemController itemController;
    uint8 heroClass;
    uint8 heroClassFromAnswerHash;
    uint8 biome;
    uint16 storyId;
    uint16 storyIdFromAnswerHash;
    uint16 pageIdFromAnswerHash;
    uint16 answerNumber;
    uint16 pageId;
    uint32 objectId;
    uint64 dungeonId;
    uint40 heroLastActionTS;
    uint80 heroTokenId;
    IStatController.ChangeableStats heroStats;
  }

  // --- WRITE ---

  function storyAction(
    address sender,
    uint64 dungeonId,
    uint32 objectId,
    uint stageId,
    address heroToken,
    uint heroTokenId,
    uint8 biome,
    uint iteration,
    bytes memory data
  ) external returns (IGOC.ActionResult memory);

  // --- READ ---

  function isStoryAvailableForHero(uint32 objectId, address heroToken, uint heroTokenId) external view returns (bool);

  function idToStory(uint16 id) external view returns (uint32 objectId);

  function heroPage(address hero, uint80 heroId, uint16 storyId) external view returns (uint16 pageId);

  function storyIds(uint32 objectId) external view returns (uint16);

  function registeredStories(uint32 objectId) external view returns (bool);

}

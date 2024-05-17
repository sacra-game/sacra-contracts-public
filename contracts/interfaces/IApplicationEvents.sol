// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IGOC.sol";
import "./IStatController.sol";
import "./IDungeonFactory.sol";
import "./IStoryController.sol";
import "./IFightCalculator.sol";

/// @notice All events of the app
interface IApplicationEvents {

  //region ------------------ StatController
  event HeroItemSlotChanged(
    address heroToken,
    uint heroTokenId,
    uint itemType,
    uint itemSlot,
    address itemToken,
    uint itemTokenId,
    bool equip,
    address caller
  );
  event CurrentStatsChanged(
    address heroToken,
    uint heroTokenId,
    IStatController.ChangeableStats change,
    bool increase,
    address caller
  );
  event BonusAttributesChanged(
    address heroToken,
    uint heroTokenId,
    bool add,
    bool temporally,
    address caller
  );
  event TemporallyAttributesCleared(address heroToken, uint heroTokenId, address caller);
  event NewHeroInited(address heroToken, uint heroTokenId, IStatController.ChangeableStats stats);
  event LevelUp(
    address heroToken,
    uint heroTokenId,
    uint heroClass,
    IStatController.CoreAttributes change
  );
  event ConsumableUsed(address heroToken, uint heroTokenId, address item);
  event RemoveConsumableUsage(address heroToken, uint heroTokenId, address item);
  event HeroCustomDataChanged(address token, uint tokenId, bytes32 index, uint value);
  event GlobalCustomDataChanged(bytes32 index, uint value);
  //endregion ------------------ StatController

  //region ------------------ DungeonFactoryController
  event DungeonLaunched(
    uint16 dungeonLogicNum,
    uint64 dungeonId,
    address heroToken,
    uint heroTokenId,
    address treasuryToken,
    uint treasuryAmount
  );

  event BossCompleted(uint32 objectId, uint biome, address hero, uint heroId);
  event FreeDungeonAdded(uint8 biome, uint64 dungeonId);

  event ObjectOpened(uint64 dungId, address hero, uint id, uint32 objId, uint iteration, uint currentStage);
  event Clear(uint64 dungId);

  event DungeonLogicRegistered(uint16 dungLogicId, IDungeonFactory.DungeonGenerateInfo info);
  event DungeonLogicRemoved(uint16 dungLogicId);
  event DungeonSpecificLogicRegistered(uint16 dungLogicId, uint biome, uint heroCls);
  event DungeonSpecificLogicRemoved(uint16 dungLogicId, uint heroLvl, uint heroCls);
  event DungeonRegistered(uint16 dungLogicId, uint64 dungeonId);
  event DungeonRemoved(uint16 dungLogicId, uint64 dungeonId);
  event MinLevelForTreasuryChanged(address token, uint level);

  event ObjectAction(
    uint64 dungId,
    IGOC.ActionResult result,
    uint currentStage,
    address heroToken,
    uint heroTokenId,
    uint newStage
  );
  /// @notice On add the item to the dungeon
  event AddTreasuryItem(uint64 dungId, address itemAdr, uint itemId);
  event AddTreasuryToken(uint64 dungId, address token, uint amount);
  event ClaimToken(uint64 dungId, address token, uint amount);
  event ClaimItem(uint64 dungId, address token, uint id);

  event Entered(uint64 dungId, address hero, uint id);
  event DungeonCompleted(uint16 dungLogicNum, uint64 dungId, address hero, uint heroId);
  event Exit(uint64 dungId, bool claim);
  event FreeDungeonRemoved(uint8 biome, uint64 dungeonId);
  event HeroCurrentDungeonChanged(address hero, uint heroId, uint64 dungeonId);
  //endregion ------------------ DungeonFactoryController

  //region ------------------ GameObjectController
  event EventRegistered(uint32 objectId, IGOC.EventRegInfo eventRegInfo);
  event StoryRegistered(uint32 objectId, uint16 storyId);
  event MonsterRegistered(uint32 objectId, IGOC.MonsterGenInfo monsterGenInfo);
  event ObjectRemoved(uint32 objectId);
  event ObjectResultEvent(
    uint64 dungeonId,
    uint32 objectId,
    IGOC.ObjectType objectType,
    address hero,
    uint heroId,
    uint8 stageId,
    uint iteration,
    bytes data,
    IGOC.ActionResult result,
    uint salt
  );
  //endregion ------------------ GameObjectController

  //region ------------------ StoryController
  event SetBurnItemsMeta(uint storyId, IStoryController.AnswerBurnRandomItemMeta meta);
  event SetNextObjRewriteMeta(uint storyId, IStoryController.NextObjRewriteMeta meta);
  event SetAnswersMeta(uint storyId, uint16[] answerPageIds, uint8[] answerHeroClasses, uint16[] answerIds);
  event SetAnswerNextPageMeta(uint storyId, IStoryController.AnswerNextPageMeta meta);
  event SetAnswerAttributeRequirements(uint storyId, IStoryController.AnswerAttributeRequirementsMeta meta);
  event SetAnswerItemRequirements(uint storyId, IStoryController.AnswerItemRequirementsMeta meta);
  event SetAnswerTokenRequirementsMeta(uint storyId, IStoryController.AnswerTokenRequirementsMeta meta);
  event SetAnswerAttributes(uint storyId, IStoryController.AnswerAttributesMeta meta);
  event SetAnswerHeroCustomDataRequirementMeta(uint storyId, IStoryController.AnswerCustomDataMeta meta);
  event SetAnswerGlobalCustomDataRequirementMeta(uint storyId, IStoryController.AnswerCustomDataMeta meta);
  event SetSuccessInfo(uint storyId, IStoryController.AnswerResultMeta meta);
  event SetFailInfo(uint storyId, IStoryController.AnswerResultMeta meta);
  event SetCustomDataResult(uint storyId, IStoryController.AnswerCustomDataResultMeta meta, IStoryController.CustomDataResult _type);
  event StoryCustomDataRequirements(uint storyId, bytes32 requiredCustomDataIndex, uint requiredCustomDataMinValue, uint requiredCustomDataMaxValue, bool requiredCustomDataIsHero);
  event StoryRequiredLevel(uint storyId, uint requiredLevel);
  event StoryFinalized(uint32 objectId, uint storyId);
  event StoryRemoved(uint32 objectId, uint storyId);

  event ItemBurned(
    address heroToken,
    uint heroTokenId,
    uint64 dungeonId,
    uint objectId,
    address nftToken,
    uint nftId,
    uint stageId,
    uint iteration
  );

  event NotEquippedItemBurned(
    address heroToken,
    uint heroTokenId,
    uint64 dungeonId,
    uint storyId,
    address nftToken,
    uint nftId,
    uint stageId,
    uint iteration
  );

  event StoryChangeAttributes(
    uint32 objectId,
    address heroToken,
    uint heroTokenId,
    uint64 dungeonId,
    uint storyId,
    uint stageId,
    uint iteration,
    int32[] attributes
  );
  //endregion ------------------ StoryController

  //region ------------------------ HeroController
  event HeroTokensVaultSet(address value);
  event HeroRegistered(address hero, uint8 heroClass, address payToken, uint payAmount);
  event HeroCreated(address hero, uint heroId, string name, address owner, string refCode);
  event BiomeChanged(address hero, uint heroId, uint8 biome);
  event LevelUp(address hero, uint heroId, address owner, IStatController.CoreAttributes change);
  event ReinforcementAsked(address hero, uint heroId, address helpHeroToken, uint helpHeroId);
  event ReinforcementReleased(address hero, uint heroId, address helperToken, uint helperId);
  event Killed(address hero, uint heroId, address killer, bytes32[] dropItems, uint dropTokenAmount);
  //endregion ------------------------ HeroController

  //region ------------------------ FightLib
  event FightResultProcessed(
    address sender,
    IFightCalculator.FightInfoInternal result,
    IFightCalculator.FightCall callData,
    uint iteration
  );
  //endregion ------------------------ FightLib

  //region ------------------------ Oracle
  event Random(uint number, uint max);
  //endregion ------------------------ Oracle

  //region ------------------------ Controller
  event OfferGovernance(address newGov);
  event GovernanceAccepted(address gov);
  event StatControllerChanged(address value);
  event StoryControllerChanged(address value);
  event GameObjectControllerChanged(address value);
  event ReinforcementControllerChanged(address value);
  event OracleChanged(address value);
  event TreasuryChanged(address value);
  event ItemControllerChanged(address value);
  event HeroControllerChanged(address value);
  event GameTokenChanged(address value);
  event DungeonFactoryChanged(address value);
  event ProxyUpdated(address proxy, address logic);
  event Claimed(address token, uint amount);
  event TokenStatusChanged(address token, bool status);
  //endregion ------------------------ Controller

  //region ------------------------ HeroTokensVault
  event Process(address token, uint amount, address from, uint toBurn, uint toTreasury, uint toGov);
  //endregion ------------------------ HeroTokensVault

  //region ------------------------ ReinforcementController
  event HeroStaked(address heroToken, uint heroId, uint biome, uint score);
  event HeroWithdraw(address heroToken, uint heroId);
  event HeroAsk(address heroToken, uint heroId);
  event TokenRewardRegistered(address heroToken, uint heroId, address token, uint amountAdded, uint totalAmount);
  event NftRewardRegistered(address heroToken, uint heroId, address token, uint id);
  event ToHelperRatioChanged(uint value);
  event ClaimedToken(address heroToken, uint heroId, address token, uint amount, address recipient);
  event ClaimedItem(address heroToken, uint heroId, address item, uint itemId, address recipient);
  event MinLevelChanged(uint8 value);
  event MinLifeChancesChanged(uint value);
  //endregion ------------------------ ReinforcementController

  //region ------------------------ Treasury
  event AssetsSentToDungeon(address dungeon, address token, uint amount);
  //endregion ------------------------ Treasury

  //region ------------------------ EventLib
  event EventResult(uint64 dungeonId, address heroToken, uint heroTokenId, uint8 stageId, IStatController.ActionInternalInfo gen, uint iteration);
  //endregion ------------------------ EventLib

  //region ------------------------ ItemStatsLib
  event ItemRegistered(address item, IItemController.RegisterItemParams info);
  event ItemRemoved(address item);
  event NewItemMinted(address item, uint itemId, IItemController.MintInfo info);
  event Equipped(address item, uint itemId, address heroToken, uint heroTokenId, uint8 itemSlot);
  event TakenOff(address item, uint itemId, address heroToken, uint heroTokenId, uint8 itemSlot, address destination);
  event ItemRepaired(address item, uint itemId, uint consumedItemId, uint16 baseDurability);
  event Augmented(address item, uint itemId, uint consumedItemId, uint8 augLevel, IItemController.AugmentInfo info);
  event NotAugmented(address item, uint itemId, uint consumedItemId, uint8 augLevel);
  event ReduceDurability(address item, uint itemId, uint newDurability);
  event Used(address item, uint tokenId, address heroToken, uint heroTokenId);
  event Destroyed(address item, uint itemId);
  //endregion ------------------------ ItemStatsLib

  //region ------------------------ NFT and GameToken (only custom events, not ERC20/721 standards)
  event ChangePauseStatus(bool value);
  event MinterChanged(address value);

  event UniqueUriChanged(uint id, string uri);
  event BaseUriChanged(string uri);

  event HeroMinted(uint heroId);
  event HeroBurned(uint heroId);
  event HeroUriByStatusChanged(string uri, uint statusLvl);

  event ItemMinted(uint tokenId);
  event ItemBurned(uint tokenId);
  event UriByRarityChanged(string uri, uint rarity);
  event SponsoredHeroCreated(address msgSender, address heroAddress, uint heroId, string heroName);
  //endregion ------------------------ NFT and GameToken (only custom events, not ERC20/721 standards)
}

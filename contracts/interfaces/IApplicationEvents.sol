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
  event HeroCustomDataChangedNg(address token, uint tokenId, bytes32 index, uint value, uint8 ngLevel);
  event HeroCustomDataCleared(address token, uint tokenId);
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
  event ExitForcibly(uint64 dungId, address hero, uint heroId);
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

  /// @notice Durability of the item was reduced to 0
  event ItemBroken(
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
  event HeroRegistered(address hero, uint8 heroClass, address payToken, uint payAmount);
  event HeroCreatedNgp(address hero, uint heroId, string name, address owner, string refCode, uint8 tier, uint8 ngLevel);
  event BiomeChanged(address hero, uint heroId, uint8 biome);
  event LevelUp(address hero, uint heroId, address owner, IStatController.CoreAttributes change);
  event ReinforcementAsked(address hero, uint heroId, address helpHeroToken, uint helpHeroId);
  event GuildReinforcementAsked(address hero, uint heroId, address helpHeroToken, uint helpHeroId);
  event OtherItemGuildReinforcement(address item, uint itemId, address hero, uint heroId, address helpHeroToken, uint helpHeroId);
  event ReinforcementReleased(address hero, uint heroId, address helperToken, uint helperId);
  event GuildReinforcementReleased(address hero, uint heroId, address helperToken, uint helperId);
  event Killed(address hero, uint heroId, address killer, bytes32[] dropItems, uint dropTokenAmount);
  event Reborn(address hero, uint heroId, uint8 newNgLevel);
  event BossKilled(address account, address hero, uint heroId, uint8 biome, uint8 newNgLevel, bool reborn, uint rewardAmount);
  event TierSetup(uint8 tier, address hero, uint72 payAmount, uint8[] slots, address[][] items);
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
  event UserControllerChanged(address value);
  event GuildControllerChanged(address value);
  event GameTokenPriceChanged(uint value);
  event RewardsPoolChanged(address value);
  event Process(address token, uint amount, address from, uint toBurn, uint toTreasury, uint toGov);
  //endregion ------------------------ Controller


  //region ------------------------ ReinforcementController
  event HeroStaked(address heroToken, uint heroId, uint biome, uint score);
  event HeroStakedV2(address heroToken, uint heroId, uint biome, uint rewardAmount);
  event HeroWithdraw(address heroToken, uint heroId);
  event HeroAsk(address heroToken, uint heroId);
  event HeroAskV2(address heroToken, uint heroId, uint hitsLast24h, uint fixedFee, uint helperRewardAmount);
  event TokenRewardRegistered(address heroToken, uint heroId, address token, uint amountAdded, uint totalAmount);
  event GuildTokenRewardRegistered(address heroToken, uint heroId, address token, uint amountAdded, uint guildId);
  event NftRewardRegistered(address heroToken, uint heroId, address token, uint id);
  event GuildNftRewardRegistered(address heroToken, uint heroId, address token, uint id, uint guildId);
  event ToHelperRatioChanged(uint value);
  event ClaimedToken(address heroToken, uint heroId, address token, uint amount, address recipient);
  event ClaimedItem(address heroToken, uint heroId, address item, uint itemId, address recipient);
  event MinLevelChanged(uint8 value);
  event MinLifeChancesChanged(uint value);
  //endregion ------------------------ ReinforcementController

  //region ------------------------ Treasury, reward pool
  event AssetsSentToDungeon(address dungeon, address token, uint amount);
  event RewardSentToUser(address receiver, address token, uint rewardAmount);
  event NotEnoughReward(address receiver, address token, uint rewardAmountToPay);
  event BaseAmountChanged(uint oldValue, uint newValue);
  //endregion ------------------------ Treasury, reward pool

  //region ------------------------ EventLib
  event EventResult(uint64 dungeonId, address heroToken, uint heroTokenId, uint8 stageId, IStatController.ActionInternalInfo gen, uint iteration);
  //endregion ------------------------ EventLib

  //region ------------------------ Item controller and helper contracts
  event ItemRegistered(address item, IItemController.RegisterItemParams info);
  event OtherItemRegistered(address item, IItemController.ItemMeta meta, bytes packedItemMetaData);
  event ItemRemoved(address item);
  event OtherItemRemoved(address item);
  event NewItemMinted(address item, uint itemId, IItemController.MintInfo info);
  event Equipped(address item, uint itemId, address heroToken, uint heroTokenId, uint8 itemSlot);
  event TakenOff(address item, uint itemId, address heroToken, uint heroTokenId, uint8 itemSlot, address destination);
  event ItemRepaired(address item, uint itemId, uint consumedItemId, uint16 baseDurability);
  event FailedToRepairItem(address item, uint itemId, uint consumedItemId, uint16 itemDurability);
  event Augmented(address item, uint itemId, uint consumedItemId, uint8 augLevel, IItemController.AugmentInfo info);
  event NotAugmented(address item, uint itemId, uint consumedItemId, uint8 augLevel);
  event ReduceDurability(address item, uint itemId, uint newDurability);
  event Used(address item, uint tokenId, address heroToken, uint heroTokenId);
  event Destroyed(address item, uint itemId);
  event FragilityReduced(address item, uint itemId, address consumedItem, uint consumedItemId, uint fragility);
  event ItemControllerHelper(address helper);
  event SetUnionConfig(uint configId, address[] items, uint[] count, address itemToMint);
  event RemoveUnionConfig(uint configId);
  event SetUnionKeyPass(address keyPassItem);
  event CombineItems(address msgSender, uint configId, address[] items, uint[][] itemIds, address mintedItem, uint mintedItemId);
  //endregion ------------------------ Item controller and helper contracts

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

  //region ------------------------ User controller
  event SetUserName(address user, string name);
  event SetUserAvatar(address user, string avatar);
  event LootBoxOpened(address user, uint lootBoxKind, address[] itemTokens, uint[] itemTokenIds);
  event LootBoxConfigChanged(uint lootBoxKind, address[] mintItems, uint32[] mintItemsChances, uint maxDropItems);
  event SetFeeRenaming(uint feeRenaming);
  event ActivityCompleted(address user, bool daily, bool weekly);
  event FameHallHeroRegistered(address hero, uint heroId, address heroOwner, uint8 openedNgLevel);
  //endregion ------------------------ User controller

  //region ------------------------ Guild

  event GuildCreated(address owner, uint guildId, string name, string urlLogo);
  event AddToGuild(uint guildId, address newUser);
  event ChangeGuildRights(uint guildId, address user, uint rights);
  event RemoveFromGuild(uint guildId, address user);
  event GuildDeleted(uint guildId);
  event GuildLevelUp(uint guildId, uint8 newLevel);
  event GuildRename(uint guildId, string newName);
  event GuildLogoChanged(uint guildId, string newLogoUrl);
  event GuildDescriptionChanged(uint guildId, string newDescription);
  event SetGuildRelation(uint guildId1, uint guildId2, bool peace);
  event TransferFromGuildBank(address user, address token, uint amount, address recipient);
  event TransferNftFromGuildBank(address user, address[] nfts, uint[] tokenIds, address recipient);
  event GuildBankDeployed(uint guildId, address guildBank);

  event SetToHelperRatio(uint guildId, uint8 value, address user);
  event TopUpGuildBank(address msgSender, uint guildId, address guildBank, uint amount);

  event GuildRequestRegistered(address msgSender, uint guildId, string userMessage, uint depositAmount);
  event GuildRequestStatusChanged(address msgSender, uint guildRequestId, uint8 newStatus, address user);
  event SetToHelperRatio(uint guildId, address msgSender, uint8 toHelperRatio);
  event SetGuildRequestDepositAmount(uint guildId, address msgSender, uint amount);
  event SetGuildBaseFee(uint fee);
  event SetPvpPointsCapacity(address msgSender, uint64 capacityPvpPoints, address[] users);
  event SetShelterController(address shelterController);
  event SetShelterAuction(address shelterAuction);
  event PayForBidFromGuildBank(uint guildId, uint amount, uint bid);
  //endregion ------------------------ Guild

  //region ------------------------ Guild shelter
  event RegisterShelter(uint sheleterId, uint price);
  event SetShelterItems(
    uint shelterId,
    address[] items,
    uint64[] pricesInPvpPoints,
    uint128[] pricesInGameTokens,
    uint16[] maxItemsPerDayThresholds
  );
  event RemoveShelterItems(uint shelterId, address[] items);
  event BuyShelter(uint guidlId, uint shelterId);
  event LeaveShelter(uint guildId, uint shelterId);
  event NewShelterBid(uint shelterId, uint buyerGuildId, uint amount);
  event RevokeShelterBid(uint shelterId);
  event UseShelterBid(uint shelterId, uint sellerGuildId, uint buyerGuidId, uint amount);
  event PurchaseShelterItem(address msgSender, address item, uint numSoldItems, uint priceInPvpPoints, uint priceInGameToken);
  event ChangeShelterOwner(uint shelterId, uint fromGuildId, uint toGuildId);
  event RestInShelter(address msgSender, address heroToken, uint heroTokenId);
  //endregion ------------------------ Guild shelter

  //region ------------------------ Guild reinforcement
  event GuildHeroStaked(address heroToken, uint heroId, uint guildId);
  event GuildHeroWithdrawn(address heroToken, uint heroId, uint guildId);
  event GuildHeroAsked(address heroToken, uint heroId, uint guildId, address user);

  /// @param user Address can be 0 if heroId was already burnt at the moment of reinforcement releasing
  event GuildHeroReleased(address heroToken, uint heroId, uint guildId, address user);
  //endregion ------------------------ Guild reinforcement

  //region ------------------------ Guild auction
  event AuctionPositionOpened(uint positionId, uint shelterId, uint sellerGuildId, address msgSender, uint minAuctionPrice);
  event AuctionPositionClosed(uint positionId, address msgSender);
  event AuctionBidOpened(uint bidId, uint positionId, uint amount, address msgSender);
  //endregion ------------------------ Guild auction

  //region ------------------------ Guild bank
  event GuildBankTransfer(address token, address recipient, uint amount);
  event GuildBankTransferNft(address to, address nft, uint tokenId);
  event GuildBankTransferNftMulti(address to, address[] nfts, uint[] tokenIds);
  //endregion ------------------------ Guild bank

  //region ------------------------ Pawnshop
  event PawnShopRouterDeployed(address pawnShop, address gameToken, address routerOwner, address deployed);
  event PawnShopRouterTransfer(address token, uint amount, address receiver);
  event PawnShopRouterBulkSell(address[] nfts, uint[] nftIds, uint[] prices, address nftOwner, uint[] positionIds);
  event PawnShopRouterClosePositions(uint[] positionIds, address receiver);
  event PawnShopRouterBulkBuy(uint[] positionIds, address receiver);

  //endregion ------------------------ Pawnshop
}

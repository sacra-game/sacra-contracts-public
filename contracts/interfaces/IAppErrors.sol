// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/// @notice All errors of the app
interface IAppErrors {

  //region ERC20Errors
  /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     */
  error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

  /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
  error ERC20InvalidSender(address sender);

  /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
  error ERC20InvalidReceiver(address receiver);

  /**
     * @dev Indicates a failure with the `spender`’s `allowance`. Used in transfers.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     * @param allowance Amount of tokens a `spender` is allowed to operate with.
     * @param needed Minimum amount required to perform a transfer.
     */
  error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

  /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
  error ERC20InvalidApprover(address approver);

  /**
   * @dev Indicates a failure with the `spender` to be approved. Used in approvals.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     */
  error ERC20InvalidSpender(address spender);

  //endregion ERC20Errors

  //region ERC721Errors

  /**
  * @dev Indicates that an address can't be an owner. For example, `address(0)` is a forbidden owner in ERC-20.
     * Used in balance queries.
     * @param owner Address of the current owner of a token.
     */
  error ERC721InvalidOwner(address owner);

  /**
   * @dev Indicates a `tokenId` whose `owner` is the zero address.
     * @param tokenId Identifier number of a token.
     */
  error ERC721NonexistentToken(uint256 tokenId);

  /**
   * @dev Indicates an error related to the ownership over a particular token. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param tokenId Identifier number of a token.
     * @param owner Address of the current owner of a token.
     */
  error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);

  /**
   * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
  error ERC721InvalidSender(address sender);

  /**
   * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
  error ERC721InvalidReceiver(address receiver);

  /**
   * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param tokenId Identifier number of a token.
     */
  error ERC721InsufficientApproval(address operator, uint256 tokenId);

  /**
   * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
  error ERC721InvalidApprover(address approver);

  /**
   * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
  error ERC721InvalidOperator(address operator);

  //endregion ERC721Errors

  error ZeroAddress();
  error ZeroValueNotAllowed();
  error ZeroToken();
  error LengthsMismatch();
  error NotEnoughBalance();
  error NotEnoughAllowance();
  error EmptyNameNotAllowed();
  error NotInitialized();
  error AlreadyInitialized();
  error ReentrancyGuardReentrantCall();
  error TooLongString();
  error AlreadyDeployed(address deployed);
  error AlreadyClaimed();

  //region Restrictions
  error ErrorNotDeployer(address sender);
  error ErrorNotGoc();
  error NotGovernance(address sender);
  error ErrorOnlyEoa();
  error NotEOA(address sender);
  error ErrorForbidden(address sender);
  error AdminOnly();
  error ErrorNotItemController(address sender);
  error ErrorNotHeroController(address sender);
  error ErrorNotDungeonFactory(address sender);
  error ErrorNotObjectController(address sender);
  error ErrorNotStoryController();
  error ErrorNotAllowedSender();
  error MintNotAllowed();
  error NotPvpController();
  //endregion Restrictions

  //region PackingLib
  error TooHighValue(uint value);
  error IntValueOutOfRange(int value);
  error OutOfBounds(uint index, uint length);
  error UnexpectedValue(uint expected, uint actual);
  error WrongValue(uint newValue, uint actual);
  error IntOutOfRange(int value);
  error ZeroValue();
  /// @notice packCustomDataChange requires an input string with two zero bytes at the beginning
  ///         0xXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX0000
  /// This error happens if these bytes are not zero
  error IncompatibleInputString();
  error IncorrectOtherItemTypeKind(uint8 kind);
  //endregion PackingLib

  //region Hero
  error ErrorHeroIsNotRegistered(address heroToken);
  error ErrorHeroIsDead(address heroToken, uint heroTokenId);
  error ErrorHeroNotInDungeon();
  error HeroInDungeon();
  error ErrorNotOwner(address token, uint tokenId);
  error ErrorNotOwnerOrHero(address token, uint tokenId);
  error Staked(address heroToken, uint heroId);
  error NameTaken();
  error TooBigName();
  error WrongSymbolsInTheName();
  error NoPayToken(address token, uint payTokenAmount);
  error AlreadyHaveReinforcement();
  /// @notice SIP-001 - Reinforcement requires 3 skills
  error ErrorReinforcementRequiresThreeSkills();
  error WrongTier(uint tier);
  error NotEnoughNgLevel(uint8 ngLevel);
  error NgpNotActive(address hero);
  error RebornNotAllowed();
  error AlreadyPrePaidHero();

  error TierForbidden();
  error SandboxPrepaidOnly();
  error SandboxNgZeroOnly();
  error SandboxModeNotAllowed();
  error SandboxUpgradeModeRequired();
  error SandboxModeRequired();
  error SandboxItemOutside();
  error SandboxItemNotActive();
  error SandboxItemNotRegistered();
  error SandboxItemAlreadyEquipped();
  error SandboxDifferentHeroesNotAllowed();
  error HeroWasTransferredBetweenAccounts();
  error SandboxFreeHeroNotAllowed();
  //endregion Hero

  //region Dungeon
  error ErrorDungeonIsFreeAlready();
  error ErrorNoEligibleDungeons();
  error ErrorDungeonBusy();
  error ErrorNoDungeonsForBiome(uint8 heroBiome);
  error ErrorDungeonCompleted();
  error ErrorAlreadyInDungeon();
  error NotEnoughTokens(uint balance, uint expectedBalance);
  error DungeonAlreadySpecific(uint16 dungNum);
  error DungeonAlreadySpecific2(uint16 dungNum);
  error WrongSpecificDungeon();
  error LastLifeChance();
  //endregion Dungeon

  //region Items
  error ErrorItemNotEligibleForTheSlot(uint itemType, uint8 itemSlot);
  error ErrorItemSlotBusyHand(uint8 slot);
  error ErrorItemSlotBusy();
  error ErrorItemNotInSlot();
  error ErrorConsumableItemIsUsed(address item);
  error ErrorCannotRemoveItemFromMap();
  error ErrorCannotRemoveDataFromMap();
  error EquippedItemsExist();
  error ItemEquipped(address item, uint itemId);
  error ZeroItemMetaType();
  error NotZeroOtherItemMetaType();
  error ZeroLevel();
  error ItemTypeChanged();
  error ItemMetaTypeChanged();
  error UnknownItem(address item);
  error ErrorEquipForbidden();
  error EquipForbiddenInDungeon();
  error TakeOffForbiddenInDungeon();
  error Consumable(address item);
  error NotConsumable(address item);
  error Broken(address item);
  error ZeroLife();
  error RequirementsToItemAttributes();
  error NotEquipped(address item);
  error ZeroDurability();
  error ZeroAugmentation();
  error TooHighAgLevel(uint8 augmentationLevel);
  error UseForbiddenZeroPayToken();
  error IncorrectMinMaxAttributeRange(int32 min, int32 max);
  error SameIdsNotAllowed();
  error ZeroFragility();
  error OtherTypeItemNotRepairable();
  error NotOther();
  error DoubleItemUsageForbidden(uint itemIndex, address[] items);
  error ItemAlreadyUsedInSlot(address item, uint8 equippedSlot);
  error WrongWayToRegisterItem();
  error UnionItemNotFound(address item);
  error WrongListUnionItemTokens(address item, uint countTokens, uint requiredCountTokens);
  error UnknownUnionConfig(uint unionConfigId);
  error UserHasNoKeyPass(address user, address keyPassItem);
  error MaxValue(uint value);
  error UnexpectedOtherItem(address item);
  error NotExist();
  error ItemNotFound(address item, uint itemId);
  error NoFirstAugmentationInfo();
  error NotAugmentationProtectiveItem(address item);
  //endregion Items

  //region Stages
  error ErrorWrongStage(uint stage);
  error ErrorNotStages();
  //endregion Stages

  //region Level
  error ErrorWrongLevel(uint heroLevel);
  error ErrorLevelTooLow(uint heroLevel);
  error ErrorHeroLevelStartFrom1();
  error ErrorWrongLevelUpSum();
  error ErrorMaxLevel();
  //endregion Level

  //region Treasure
  error ErrorNotValidTreasureToken(address treasureToken);
  //endregion Treasure

  //region State
  error ErrorPaused();
  error ErrorNotReady();
  error ErrorNotObject1();
  error ErrorNotObject2();
  error ErrorNotCompleted();
  //endregion State

  //region Biome
  error ErrorNotBiome();
  error ErrorIncorrectBiome(uint biome);
  error TooHighBiome(uint biome);
  //endregion Biome

  //region Misc
  error ErrorWrongMultiplier(uint multiplier);
  error ErrorNotEnoughMana(uint32 mana, uint requiredMana);
  error ErrorExperienceMustNotDecrease();
  error ErrorNotEnoughExperience();
  error ErrorNotChances();
  error ErrorNotEligible(address heroToken, uint16 dungNum);
  error ErrorZeroKarmaNotAllowed();
  //endregion Misc

  //region GOC
  error GenObjectIdBiomeOverflow(uint8 biome);
  error GenObjectIdSubTypeOverflow(uint subType);
  error GenObjectIdIdOverflow(uint id);
  error UnknownObjectTypeGoc1(uint8 objectType);
  error UnknownObjectTypeGoc2(uint8 objectType);
  error UnknownObjectTypeGocLib1(uint8 objectType);
  error UnknownObjectTypeGocLib2(uint8 objectType);
  error UnknownObjectTypeForSubtype(uint8 objectSubType);
  error FightDelay();
  error ZeroChance();
  error TooHighChance(uint32 chance);
  error TooHighRandom(uint random);
  error EmptyObjects();
  error ObjectNotFound();
  error WrongGetObjectTypeInput();
  error WrongChances(uint32 chances, uint32 maxChances);
  //endregion GOC

  //region Story
  error PageNotRemovedError(uint pageId);
  error NotItem1();
  error NotItem2();
  error NotRandom(uint32 random);
  error NotHeroData();
  error NotGlobalData();
  error ZeroStoryIdRemoveStory();
  error ZeroStoryIdStoryAction();
  error ZeroStoryIdAction();
  error NotEnoughAmount(uint balance, uint requiredAmount);
  error NotAnswer();
  error AnswerStoryIdMismatch(uint16 storyId, uint16 storyIdFromAnswerHash);
  error AnswerPageIdMismatch(uint16 pageId, uint16 pageIdFromAnswerHash);
  error NotSkippableStory();
  error StoryNotPassed();
  error SkippingNotAllowed();
  //endregion Story

  //region FightLib
  error NotMagic();
  error NotAType(uint atype);
  //endregion FightLib

  //region MonsterLib
  error NotYourDebuffItem();
  error UnknownAttackType(uint attackType);
  error NotYourAttackItem();
  /// @notice The skill item cannot be used because it doesn't belong either to the hero or to the hero's helper
  error NotYourBuffItem();
  //endregion MonsterLib

  //region GameToken
  error ApproveToZeroAddress();
  error MintToZeroAddress();
  error TransferToZeroAddress();
  error TransferAmountExceedsBalance(uint balance, uint value);
  error InsufficientAllowance();
  error BurnAmountExceedsBalance();
  error NotMinter(address sender);
  //endregion GameToken

  //region NFT
  error TokenTransferNotAllowed();
  error IdOverflow(uint id);
  error NotExistToken(uint tokenId);
  error EquippedItemIsNotAllowedToTransfer(uint tokenId);
  //endregion NFT

  //region CalcLib
  error TooLowX(uint x);
  //endregion CalcLib

  //region Controller
  error NotFutureGovernance(address sender);
  //endregion Controller

  //region Oracle
  error OracleWrongInput();
  //endregion Oracle

  //region ReinforcementController
  error AlreadyStaked();
  error MaxFee(uint8 fee);
  error MinFee(uint8 fee);
  error StakeHeroNotStats();
  error NotStaked();
  error NoStakedHeroes();
  error GuildHelperNotAvailable(uint guildId, address helper, uint helperId);
  error PvpStaked();
  error HelperNotAvailableInGivenBiome();
  //endregion ReinforcementController

  //region SponsoredHero
  error InvalidHeroClass();
  error ZeroAmount();
  error InvalidProof();
  error NoHeroesAvailable();
  error AlreadyRegistered();
  //endregion SponsoredHero

  //region SacraRelay
  error SacraRelayNotOwner();
  error SacraRelayNotDelegator();
  error SacraRelayNotOperator();
  error SacraRelayInvalidChainId(uint callChainId, uint blockChainId);
  error SacraRelayInvalidNonce(uint callNonce, uint txNonce);
  error SacraRelayDeadline();
  error SacraRelayDelegationExpired();
  error SacraRelayNotAllowed();
  error SacraRelayInvalidSignature();
  /// @notice This error is generated when custom error is caught
  /// There is no info about custom error in SacraRelay
  /// but you can decode custom error by selector, see tests
  error SacraRelayNoErrorSelector(bytes4 selector, string tracingInfo);
  /// @notice This error is generated when custom error is caught
  /// There is no info about custom error in SacraRelay
  /// but you can decode custom error manually from {errorBytes} as following:
  /// if (keccak256(abi.encodeWithSignature("MyError()")) == keccak256(errorBytes)) { ... }
  error SacraRelayUnexpectedReturnData(bytes errorBytes, string tracingInfo);
  error SacraRelayCallToNotContract(address notContract, string tracingInfo);
  //endregion SacraRelay

  //region Misc
  error UnknownHeroClass(uint heroClass);
  error AbsDiff(int32 a, int32 b);
  //endregion Misc

  //region ------------------------ UserController
  error NoAvailableLootBox(address msgSender, uint lootBoxKind);
  error FameHallHeroAlreadyRegistered(uint8 openedNgLevel);

  //endregion ------------------------ UserController

  //region ------------------------ Guilds
  error AlreadyGuildMember();
  error NotGuildMember();
  error WrongGuild();
  error GuildActionForbidden(uint right);
  error GuildHasMaxSize(uint guildSize);
  error GuildHasMaxLevel(uint level);
  error TooLongUrl();
  error TooLongDescription();
  error CannotRemoveGuildOwnerFromNotEmptyGuild();
  error GuildControllerOnly();
  error GuildAlreadyHasShelter();
  error ShelterIsBusy();
  error ShelterIsNotRegistered();
  error ShelterIsNotOwnedByTheGuild();
  error ShelterIsInUse();
  error GuildHasNoShelter();
  error ShelterBidIsNotAllowedToBeUsed();
  error ShelterHasHeroesInside();
  error SecondGuildAdminIsNotAllowed();
  error NotEnoughGuildBankBalance(uint guildId);

  error GuildReinforcementCooldownPeriod();
  error NoStakedGuildHeroes();
  error NotStakedInGuild();
  error ShelterHasNotEnoughLevelForReinforcement();
  error NotBusyGuildHelper();
  error TooLowGuildLevel();

  /// @notice Target biome can be selected only once per epoch
  error BiomeAlreadySelected();
  error NoDominationRequest();
  error PvpFightIsNotPrepared(uint8 biome, uint32 week, address user);
  error PvpFightIsCompleted(uint8 biome, uint32 week, address user);
  error TooLowMaxCountTurns();
  error UserTokensVaultAlreadySet();

  error DifferentBiomeInPvpFight();
  error PvpFightOpponentNotFound();
  error PvpHeroHasInitializedFight();
  error PvpHeroNotRegistered();

  /// @notice User should unregister pvp-hero from prev biome and only then register it in the new biome
  error UserHasRegisteredPvpHeroInBiome(uint8 biome);
  error UserHasRegisteredPvpHero();
  error UserNotAllowedForPvpInCurrentEpoch(uint week);

  error UnknownPvpStrategy();

  error GuildRequestNotActive();
  error GuildRequestNotAvailable();
  error NotAdminCannotAddMemberWithNotZeroRights();
  //endregion ------------------------ Guilds

  //region ------------------------ Shelters
  error ErrorNotShelterController();
  error ErrorNotGuildController();
  error ShelterHasNotItem(uint shelterId, address item);
  error MaxNumberItemsSoldToday(uint numSoldItems, uint limit);
  error GuildHasNotEnoughPvpPoints(uint64 pointsAvailable, uint pointRequired);
  error FreeShelterItemsAreNotAllowed(uint shelterId, address item);
  error TooLowShelterLevel(uint8 shelterLevel, uint8 allowedShelterLevel);
  error NotEnoughPvpPointsCapacity(address user, uint usedPoints, uint pricePvpPoints, uint64 capactiy);
  error IncorrectShelterLevel(uint8 shelterLevel);
  //endregion ------------------------ Shelters

  //region ------------------------ Auction
  error WrongAuctionPosition();
  error AuctionPositionClosed();
  error AuctionBidOpened(uint positionId);
  error TooLowAmountToBid();
  error AuctionEnded();
  error TooLowAmountForNewBid();
  error AuctionSellerOnly();
  error AuctionBuyerOnly();
  error AuctionBidNotFound();
  error AuctionBidClosed();
  error OnlyShelterAuction();
  error CannotCloseLastBid();
  error AuctionNotEnded();
  error NotShelterAuction();
  error AuctionPositionOpened(uint positionId);
  error AuctionSellerCannotBid();
  error AuctionGuildWithShelterCannotBid();
  error AuctionBidExists();
  //endregion ------------------------ Auction

  //region ------------------------ Pawnshop
  error AuctionPositionNotSupported(uint positionId);
  error PositionNotSupported(uint positionId);
  error NotNftPositionNotSupported(uint positionId);
  error CallFailed(bytes callResultData);

  error PawnShopZeroOwner();
  error PawnShopZeroFeeRecipient();
  error PawnShopNotOwner();
  error PawnShopAlreadyAnnounced();
  error PawnShopTimeLock();
  error PawnShopWrongAddressValue();
  error PawnShopWrongUintValue();
  error PawnShopZeroAddress();
  error PawnShopTooHighValue();
  error PawnShopZeroAToken();
  error PawnShopZeroCToken();
  error PawnShopWrongAmounts();
  error PawnShopPosFeeForInstantDealForbidden();
  error PawnShopPosFeeAbsurdlyHigh();
  error PawnShopIncorrect();
  error PawnShopWrongId();
  error PawnShopNotBorrower();
  error PawnShopPositionClosed();
  error PawnShopPositionExecuted();
  error PawnShopWrongBidAmount();
  error PawnShopTooLowBid();
  error PawnShopNewBidTooLow();
  error PawnShopBidAlreadyExists();
  error PawnShopAuctionEnded();
  error PawnShopNotLender();
  error PawnShopTooEarlyToClaim();
  error PawnShopPositionNotExecuted();
  error PawnShopAlreadyClaimed();
  error PawnShopAuctionNotEnded();
  error PawnShopBidClosed();
  error PawnShopNoBids();
  error PawnShopAuctionBidNotFound();
  error PawnShopWrongBid();
  error PawnShopBidNotFound();

  //endregion ------------------------ Pawnshop
}


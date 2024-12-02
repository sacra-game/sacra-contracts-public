// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../openzeppelin/Math.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IDungeonFactory.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IGuildController.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IGameToken.sol";
import "../interfaces/IMinter.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IReinforcementController.sol";
import "../lib/CalcLib.sol";
import "../lib/PackingLib.sol";
import "../lib/AppLib.sol";

library ReinforcementControllerLib {
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using EnumerableMap for EnumerableMap.Bytes32ToUintMap;
  using PackingLib for bytes32;
  using PackingLib for address;
  using PackingLib for uint8[];

  //region ------------------------ Constants

  /// @dev keccak256(abi.encode(uint256(keccak256("reinforcement.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant MAIN_STORAGE_LOCATION = 0x5a053c541e08c6bd7dfc3042a100e83af246544a23ecda1a47bf22b441b00c00;
  uint internal constant _SEARCH_WINDOW = 100;
  int32 internal constant _ATTRIBUTES_RATIO = 20;
  uint internal constant _FEE_MIN = 10;
  uint internal constant _TO_HELPER_RATIO_MAX = 50;
  uint internal constant _STAKE_REDUCE_DELAY = 7 days;
  uint internal constant _DELAY_FACTOR = 2;
  uint internal constant _SIP001_COUNT_REQUIRED_SKILLS = 3;

  /// @notice Min level of shelter where guild reinforcement is allowed. 2, 3 - allowed, 1 - forbidden.
  uint internal constant MIN_SHELTER_LEVEL_GUILD_REINFORCEMENT_ALLOWED = 2;

  /// @notice Guild hero staking is not allowed during following period after withdrawing the hero
  uint internal constant HERO_COOLDOWN_PERIOD_AFTER_GUILD_HERO_WITHDRAWING = 1 days;

  uint internal constant STATUS_HELPER_FREE = 0;

  /// @notice 24 hours is divided on "baskets". Each basket covers given interval of the hours.
  uint constant internal BASKET_INTERVAL = 3;
  //endregion ------------------------ Constants

  //region ------------------------ Restrictions

  function onlyHeroController(IController controller) internal view returns (address heroController){
    heroController = controller.heroController();
    if (heroController != msg.sender) revert IAppErrors.ErrorNotHeroController(msg.sender);
  }

  /// @notice Ensure that the user is a member of a guild, the guild has a shelter and the shelter has level > 1
  function onlyGuildWithShelterEnoughLevel(IGuildController gc, uint guildId) internal view {
    uint shelterId = gc.guildToShelter(guildId);
    if (shelterId == 0) revert IAppErrors.GuildHasNoShelter();

    (, uint8 shelterLevel, ) = PackingLib.unpackShelterId(shelterId);
    if (shelterLevel < MIN_SHELTER_LEVEL_GUILD_REINFORCEMENT_ALLOWED) revert IAppErrors.ShelterHasNotEnoughLevelForReinforcement();
  }

  function onlyNotPausedEoaOwner(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId) internal view {
    if (!isEoa) revert IAppErrors.ErrorOnlyEoa();
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
    if (IERC721(heroToken).ownerOf(heroId) != msgSender) revert IAppErrors.ErrorNotOwner(heroToken, heroId);
  }

  function onlyDungeonFactory(IController controller) internal view {
    if (controller.dungeonFactory() != msg.sender) revert IAppErrors.ErrorNotDungeonFactory(msg.sender);
  }

  function onlyDeployer(IController controller) internal view {
    if (!controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }

  function _checkStakeAllowed(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId)
  internal view returns (IHeroController){
    onlyNotPausedEoaOwner(isEoa, controller, msgSender, heroToken, heroId);

    IHeroController hc = IHeroController(controller.heroController());
    if (hc.heroClass(heroToken) == 0) revert IAppErrors.ErrorHeroIsNotRegistered(heroToken);

    if (IDungeonFactory(controller.dungeonFactory()).currentDungeon(heroToken, heroId) != 0) revert IAppErrors.HeroInDungeon();
    if (isStaked(heroToken, heroId)) revert IAppErrors.AlreadyStaked();

    return hc;
  }

  function _checkWithdrawAllowed(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId) internal view {
    onlyNotPausedEoaOwner(isEoa, controller, msgSender, heroToken, heroId);
    if (IHeroController(controller.heroController()).heroClass(heroToken) == 0) revert IAppErrors.ErrorHeroIsNotRegistered(heroToken);
  }

  function _memberOf(IController controller, address msgSender) internal view returns (IGuildController gc, uint guildId) {
    gc = IGuildController(controller.guildController());
    guildId = gc.memberOf(msgSender);
    if (guildId == 0) revert IAppErrors.NotGuildMember();
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ VIEWS

  function _S() internal pure returns (IReinforcementController.MainState storage s) {
    assembly {
      s.slot := MAIN_STORAGE_LOCATION
    }
    return s;
  }

  function toHelperRatio(IController controller, address heroToken, uint heroId) internal view returns (uint) {
    // Assume that this function is called by dungeonLib before reinforcement releasing
    // so for guild-reinforcement we can detect guild by guildHelperOf
    uint guildId = busyGuildHelperOf(heroToken, heroId);
    if (guildId == 0) {
      // Helper doesn't receive any reward at the end of the dungeon in Reinforcement V2
      // fixed reward-amount is paid to the helper in askHeroV2, that's all
      return 0;
    }  else {
      // guild reinforcement
      (, , , , , uint _toHelperRatio) = IGuildController(controller.guildController()).getGuildData(guildId);
      return _toHelperRatio;
    }
  }

  function heroInfo(address heroToken, uint heroId) internal view returns (IReinforcementController.HeroInfo memory) {
    return unpackHeroInfo(_S()._stakedHeroes[heroToken.packNftId(heroId)]);
  }

  function heroInfoV2(address heroToken, uint heroId) internal view returns (IReinforcementController.HeroInfoV2 memory) {
    return _S().stakedHeroesV2[heroToken.packNftId(heroId)];
  }

  /// @notice Check if the hero is staked using classic or guild reinforcement
  function isStaked(address heroToken, uint heroId) internal view returns (bool) {
    return isStakedV2(heroToken, heroId)
      || getStakedHelperGuild(heroToken, heroId) != 0
      || isStakedV1(heroToken, heroId);
  }

  function isStakedV1(address heroToken, uint heroId) internal view returns (bool) {
    return heroInfo(heroToken, heroId).biome != 0;
  }

  function isStakedV2(address heroToken, uint heroId) internal view returns (bool) {
    return heroInfoV2(heroToken, heroId).biome != 0;
  }

  /// @return Return the guild in which the hero is staked for guild reinforcement
  function getStakedHelperGuild(address heroToken, uint heroId) internal view returns (uint) {
    return _S().stakedGuildHeroes[heroToken.packNftId(heroId)];
  }

  function stakedGuildHelpersLength(uint guildId) internal view returns (uint) {
    return _S().guildHelpers[guildId].length();
  }

  function stakedGuildHelperByIndex(uint guildId, uint index) internal view returns (
    address helper,
    uint helperId,
    uint busyInGuildId
  ) {
    bytes32 packedHelper;
    (packedHelper, busyInGuildId) =  _S().guildHelpers[guildId].at(index);
    (helper, helperId) = PackingLib.unpackNftId(packedHelper);
  }

  function earned(address heroToken, uint heroId) internal view returns (
    address[] memory tokens,
    uint[] memory amounts,
    address[] memory nfts,
    uint[] memory ids
  ){
    EnumerableMap.AddressToUintMap storage erc20Rewards = _S()._heroTokenRewards[heroToken.packNftId(heroId)];
    uint length = erc20Rewards.length();
    tokens = new address[](length);
    amounts = new uint[](length);
    for (uint i; i < length; ++i) {
      (tokens[i], amounts[i]) = erc20Rewards.at(i);
    }

    bytes32[] storage nftRewards = _S()._heroNftRewards[heroToken.packNftId(heroId)];
    length = nftRewards.length;
    nfts = new address[](length);
    ids = new uint[](length);
    for (uint i; i < length; ++i) {
      (nfts[i], ids[i]) = PackingLib.unpackNftId(nftRewards[i]);
    }
  }

  /// @notice Return the guild in which the hero is currently asked for guild reinforcement
  function busyGuildHelperOf(address heroToken, uint heroId) internal view returns (uint guildId) {
    return _S().busyGuildHelpers[heroToken.packNftId(heroId)];
  }

  /// @notice Return moment of last withdrawing of the hero from guild reinforcement
  function lastGuildHeroWithdrawTs(address heroToken, uint heroId) internal view returns (uint guildId) {
    return _S().lastGuildHeroWithdrawTs[heroToken.packNftId(heroId)];
  }

  function getConfigV2() internal view returns (uint32 minNumberHits, uint32 maxNumberHits, uint32 lowDivider, uint32 highDivider, uint8 levelLimit) {
    return PackingLib.unpackConfigReinforcementV2(
      bytes32(_S().configParams[IReinforcementController.ConfigParams.V2_MIN_MAX_BOARD_0])
    );
  }

  function getFeeAmount(address gameToken, uint hitsLast24h, uint8 biome) internal view returns (uint feeAmount) {
    return _getFeeAmount(gameToken, hitsLast24h, biome);
  }

  function getHitsNumberPerLast24Hours(uint8 biome, uint blockTimestamp) internal view returns (uint hitsLast24h) {
    IReinforcementController.LastWindowsV2 memory stat24h = _S().stat24hV2[biome];
    (hitsLast24h, ) = getHitsNumberPerLast24Hours(blockTimestamp, BASKET_INTERVAL, stat24h);
  }

  function getLastWindowsV2(uint8 biome) internal view returns (IReinforcementController.LastWindowsV2 memory) {
    return _S().stat24hV2[biome];
  }

  function heroesByBiomeV2Length(uint8 biome) internal view returns (uint) {
    return _S().heroesByBiomeV2[biome].length();
  }

  function heroesByBiomeV2ByIndex(uint8 biome, uint index) internal view returns (address helper, uint helperId) {
    bytes32 packedHelper =_S().heroesByBiomeV2[biome].at(index);
    (helper, helperId) = PackingLib.unpackNftId(packedHelper);
  }

  function heroesByBiomeV2(uint8 biome) internal view returns (address[] memory helpers, uint[] memory helperIds) {
    EnumerableSet.Bytes32Set storage packedHeroes = _S().heroesByBiomeV2[biome];
    uint len = packedHeroes.length();

    helpers = new address[](len);
    helperIds = new uint[](len);

    for (uint i; i < len; ++i) {
      (helpers[i], helperIds[i]) = PackingLib.unpackNftId(packedHeroes.at(i));
    }
    return (helpers, helperIds);
  }

  //endregion ------------------------ VIEWS

  //region ------------------------ GOV ACTIONS
  function setConfigV2(IController controller, IReinforcementController.ConfigReinforcementV2 memory config) internal {
    onlyDeployer(controller);
    _S().configParams[IReinforcementController.ConfigParams.V2_MIN_MAX_BOARD_0] = uint(
      PackingLib.packConfigReinforcementV2(config.minNumberHits, config.maxNumberHits, config.lowDivider, config.highDivider, config.levelLimit)
    );
  }

  //endregion ------------------------ GOV ACTIONS

  //region ------------------------ Reinforcement V1
  /// @notice Reverse operation for {stakeHero}
  function withdrawHero(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId) internal {
    IReinforcementController.MainState storage s = _S();

    _checkWithdrawAllowed(isEoa, controller, msgSender, heroToken, heroId);

    (uint8 biome, , , ) = PackingLib.unpackReinforcementHeroInfo(s._stakedHeroes[heroToken.packNftId(heroId)]);
    if (biome == 0) revert IAppErrors.NotStaked();

    s._internalIdsByBiomes[biome].remove(heroToken.packNftId(heroId));
    delete s._stakedHeroes[heroToken.packNftId(heroId)];

    emit IApplicationEvents.HeroWithdraw(heroToken, heroId);
  }

  function unpackHeroInfo(bytes32 packed) internal pure returns (IReinforcementController.HeroInfo memory info) {
    (info.biome, info.score, info.fee, info.stakeTs) = PackingLib.unpackReinforcementHeroInfo(packed);
    return info;
  }
  //endregion ------------------------ Reinforcement V1

  //region ------------------------ Rewards for reinforcement of any kind
  /// @notice For classic reinforcement: register reward in _S(), keep tokens on balance of this contract
  /// For guild reinforcement: re-send reward to the guild bank.
  /// @dev Only for dungeon. Assume the tokens already sent to this contract.
  function registerTokenReward(IController controller, address heroToken, uint heroId, address token, uint amount) internal {
    onlyDungeonFactory(controller);

    uint guildId = busyGuildHelperOf(heroToken, heroId);
    if (guildId == 0) {
      // classic reinforcement: save all rewards to _heroTokenRewards
      EnumerableMap.AddressToUintMap storage rewards = _S()._heroTokenRewards[heroToken.packNftId(heroId)];

      (,uint existAmount) = rewards.tryGet(token);
      rewards.set(token, existAmount + amount);

      emit IApplicationEvents.TokenRewardRegistered(heroToken, heroId, token, amount, existAmount + amount);
    } else {
      // guild reinforcement: send all rewards to guild bank
      address guildBank = IGuildController(controller.guildController()).getGuildBank(guildId);
      IERC20(token).transfer(guildBank, amount);
      emit IApplicationEvents.GuildTokenRewardRegistered(heroToken, heroId, token, amount, guildId);
    }
  }

  /// @notice For classic reinforcement: register reward in _S(), keep the token on balance of this contract
  /// For guild reinforcement: re-send NFT-reward to the guild bank.
  /// @dev Only for dungeon. Assume the NFT already sent to this contract.
  function registerNftReward(IController controller, address heroToken, uint heroId, address token, uint tokenId) internal {
    onlyDungeonFactory(controller);

    uint guildId = busyGuildHelperOf(heroToken, heroId);
    if (guildId == 0) {
        // classic reinforcement: save all rewards to _heroNftRewards
      _S()._heroNftRewards[heroToken.packNftId(heroId)].push(token.packNftId(tokenId));

      emit IApplicationEvents.NftRewardRegistered(heroToken, heroId, token, tokenId);
    } else {
      // guild reinforcement: send all rewards to guild bank
      address guildBank = IGuildController(controller.guildController()).getGuildBank(guildId);
      IERC721(token).transferFrom(address(this), guildBank, tokenId);

      emit IApplicationEvents.GuildNftRewardRegistered(heroToken, heroId, token, tokenId, guildId);
    }
  }

  function claimAll(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId) internal {
    onlyNotPausedEoaOwner(isEoa, controller, msgSender, heroToken, heroId);

    _claimAllTokenRewards(heroToken, heroId, msgSender);
    _claimAllNftRewards(heroToken, heroId, msgSender);
  }

  function claimNft(
    bool isEoa,
    IController controller,
    address msgSender,
    address heroToken,
    uint heroId,
    uint countNft
  ) internal {
    onlyNotPausedEoaOwner(isEoa, controller, msgSender, heroToken, heroId);

    _claimNftRewards(heroToken, heroId, msgSender, countNft);
  }
  //endregion ------------------------ Rewards for reinforcement of any kind

  //region ------------------------ Guild reinforcement
  function stakeGuildHero(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId) internal {
    _checkStakeAllowed(isEoa, controller, msgSender, heroToken, heroId);

    IReinforcementController.MainState storage s = _S();
    bytes32 packedHero = heroToken.packNftId(heroId);

    (, uint guildId) = _memberOf(controller, msgSender);

    uint lastGuildHeroWithdraw = s.lastGuildHeroWithdrawTs[packedHero];
    if (block.timestamp - HERO_COOLDOWN_PERIOD_AFTER_GUILD_HERO_WITHDRAWING < lastGuildHeroWithdraw) revert IAppErrors.GuildReinforcementCooldownPeriod();

    s.stakedGuildHeroes[packedHero] = guildId;

    // there is a chance that the hero is being used in reinforcement as result of previous staking
    uint busyByGuidId = s.busyGuildHelpers[packedHero];
    s.guildHelpers[guildId].set(packedHero, busyByGuidId);

    emit IApplicationEvents.GuildHeroStaked(heroToken, heroId, guildId);
  }

  function withdrawGuildHero(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId) internal {
    _checkWithdrawAllowed(isEoa, controller, msgSender, heroToken, heroId);

    IReinforcementController.MainState storage s = _S();
    bytes32 packedHero = heroToken.packNftId(heroId);

    uint guildId = s.stakedGuildHeroes[packedHero];
    if (guildId == 0) revert IAppErrors.NotStakedInGuild();

    delete s.stakedGuildHeroes[packedHero];
    if (s.guildHelpers[guildId].contains(packedHero)) {
      s.guildHelpers[guildId].remove(packedHero);
    }

    s.lastGuildHeroWithdrawTs[packedHero] = block.timestamp;

    emit IApplicationEvents.GuildHeroWithdrawn(heroToken, heroId, guildId);
  }

  /// @param hero Assume that the hero has no reinforcement, it's checked inside ItemController
  /// @param helper Desired helper. It should be staked by a member of the user's guild.
  function askGuildHero(IController controller, address hero, uint heroId, address helper, uint helperId) internal returns (
    int32[] memory attributes
  ) {
    onlyHeroController(controller);

    address user = IERC721(hero).ownerOf(heroId);
    IReinforcementController.MainState storage s = _S();
    (IGuildController gc, uint guildId) = _memberOf(controller, user);

    onlyGuildWithShelterEnoughLevel(gc, guildId);

    // ensure that the helper is free
    bytes32 packedHelper = PackingLib.packNftId(helper, helperId);
    EnumerableMap.Bytes32ToUintMap storage guildHelpers = s.guildHelpers[guildId];
    if (!guildHelpers.contains(packedHelper)) revert IAppErrors.GuildHelperNotAvailable(guildId, helper, helperId);

    // mark the helper as busy
    guildHelpers.set(packedHelper, guildId);
    s.busyGuildHelpers[packedHelper] = guildId;

    attributes = _getReinforcementAttributes(controller, helper, helperId);

    emit IApplicationEvents.GuildHeroAsked(helper, helperId, guildId, user);
    return attributes;
  }

  function releaseGuildHero(IController controller, address helperHeroToken, uint helperHeroTokenId) internal {
    onlyHeroController(controller);

    bytes32 packedHero = helperHeroToken.packNftId(helperHeroTokenId);
    IReinforcementController.MainState storage s = _S();

    address owner;
    try IERC721(helperHeroToken).ownerOf(helperHeroTokenId) returns (address heroOwner) {
      // there is a chance that the helperId is already burnt
      // see test "use guild reinforcement - burn the helper-hero that is being used by reinforcement"
      // so, we cannot check IERC721(helperHeroToken).ownerOf(helperHeroTokenId) here without try/catch
      owner = heroOwner;
    } catch {}

    if (s.busyGuildHelpers[packedHero] == 0) revert IAppErrors.NotBusyGuildHelper();

    uint guildIdStakedIn = s.stakedGuildHeroes[packedHero];
    if (guildIdStakedIn != 0) {
      s.guildHelpers[guildIdStakedIn].set(packedHero, 0); // free for use in guild reinforcement again
    }

    s.busyGuildHelpers[packedHero] = 0;

    emit IApplicationEvents.GuildHeroReleased(helperHeroToken, helperHeroTokenId, guildIdStakedIn, owner);
  }
  //endregion ------------------------ Guild reinforcement

  //region ------------------------ Reinforcement V2
  /// @notice Stake hero in reinforcement-v2
  /// @param rewardAmount Reward required by the helper for the help.
  function stakeHeroV2(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId, uint rewardAmount) internal {
    IReinforcementController.MainState storage s = _S();
    onlyNotPausedEoaOwner(isEoa, controller, msgSender, heroToken, heroId);

    if (rewardAmount == 0) revert IAppErrors.ZeroAmount();

    IHeroController heroController = _checkStakeAllowed(isEoa, controller, msgSender, heroToken, heroId);
    IStatController statController = IStatController(controller.statController());

    uint8 biome = heroController.heroBiome(heroToken, heroId);

    {
      (, , , , uint8 levelLimit) = getConfigV2();
      IStatController.ChangeableStats memory stats = statController.heroStats(heroToken, heroId);
      if (levelLimit != 0) { // levelLimit can be 0 in functional tests
        if (stats.level > levelLimit && (stats.level - levelLimit) / levelLimit > biome) revert IAppErrors.StakeHeroNotStats();
      }
      if (stats.lifeChances == 0) revert IAppErrors.ErrorHeroIsDead(heroToken, heroId);
    }

    s.heroesByBiomeV2[biome].add(heroToken.packNftId(heroId));

    s.stakedHeroesV2[heroToken.packNftId(heroId)] = IReinforcementController.HeroInfoV2({
      biome: biome,
      stakeTs: uint64(block.timestamp),
      rewardAmount: uint128(rewardAmount)
    });

    emit IApplicationEvents.HeroStakedV2(heroToken, heroId, biome, rewardAmount);
  }

  /// @notice Reverse operation for {stakeHeroV2}
  function withdrawHeroV2(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId) internal {
    IReinforcementController.MainState storage s = _S();

    _checkWithdrawAllowed(isEoa, controller, msgSender, heroToken, heroId);
    bytes32 packedHero = heroToken.packNftId(heroId);

    IReinforcementController.HeroInfoV2 memory _heroInfoV2 = s.stakedHeroesV2[packedHero];
    if (_heroInfoV2.biome == 0) revert IAppErrors.NotStaked();

    s.heroesByBiomeV2[_heroInfoV2.biome].remove(packedHero);
    delete s.stakedHeroesV2[packedHero];

    emit IApplicationEvents.HeroWithdraw(heroToken, heroId);
  }

  /// @notice {hero} asks help of the {helper}
  /// Hero owner sends reward amount to the helper owner as the reward for the help.
  /// Hero owner sends fixed fee to controller using standard process-routine.
  /// Size of the fixed fee depends on total number of calls of {askHeroV2} for last 24 hours since the current moment.
  /// Durability of all equipped items of the helper are reduced.
  /// Assume, that hero owner approves rewardAmount + fixed fee to reinforcementController-contract
  /// - rewardAmount: amount required by the helper (see {heroInfoV2})
  /// - fixed fee: fee taken by controller (see {getFeeAmount})
  function askHeroV2(IController controller, address hero, uint heroId, address helper, uint helperId, uint blockTimestamp) internal returns (
    int32[] memory attributes
  ) {
    // assume that the signer (HeroController) has checked that the hero and helper are registered, controller is not paused
    uint8 heroBiome;
    {
      address heroController = onlyHeroController(controller);
      heroBiome = IHeroController(heroController).heroBiome(hero, heroId);
    }

    address gameToken = controller.gameToken();

    IReinforcementController.HeroInfoV2 memory _heroInfo = _S().stakedHeroesV2[helper.packNftId(helperId)];
    if (_heroInfo.biome != heroBiome) revert IAppErrors.HelperNotAvailableInGivenBiome();

    // calculate number of calls for the last 24 hours starting from the current moment
    uint hitsLast24h = _getHitsLast24h(heroBiome, blockTimestamp);

    // calculate fixed fee and send it to the treasury
    uint fixedFee = _getFeeAmount(gameToken, hitsLast24h, heroBiome);

    {
      address heroOwner = IERC721(hero).ownerOf(heroId);
      IERC20(gameToken).transferFrom(heroOwner, address(this), fixedFee + _heroInfo.rewardAmount);
    }

    { // send reward amount from msgSender to helper
      address helperOwner = IERC721(helper).ownerOf(helperId);
      IERC20(gameToken).transfer(helperOwner, _heroInfo.rewardAmount);
    }

    AppLib.approveIfNeeded(gameToken, fixedFee, address(controller));
    controller.process(gameToken, fixedFee, address(this));

    attributes = _getReinforcementAttributes(controller, helper, helperId);

    // reduceDurability of all equipped items of the helper
    IItemController(controller.itemController()).reduceDurability(helper, helperId, heroBiome, true);

    emit IApplicationEvents.HeroAskV2(helper, helperId, hitsLast24h, fixedFee, _heroInfo.rewardAmount);

    return attributes;
  }

  //endregion ------------------------ Reinforcement V2

  //region ------------------------ Internal logic
  /// @notice Increment counter of hits, calculate actual number of hits for 24 hours starting from the current moment
  /// @return hitsLast24h Number of calls for the last 24 hours, decimals 18
  function _getHitsLast24h(uint biome, uint blockTimestamp) internal returns (uint hitsLast24h) {
    IReinforcementController.LastWindowsV2 memory stat24h = _S().stat24hV2[biome];
    (hitsLast24h, stat24h) = getHitsNumberPerLast24Hours(blockTimestamp, BASKET_INTERVAL, stat24h);
    _S().stat24hV2[biome] = stat24h; // save updated statistics for last 24 hours
  }

  function _getReinforcementAttributes(IController controller, address heroToken, uint heroTokenId) internal view returns (
    int32[] memory attributes
  ) {
    IStatController sc = IStatController(controller.statController());
    uint[] memory indexes = new uint[](12);

    indexes[0] = uint(IStatController.ATTRIBUTES.STRENGTH);
    indexes[1] = uint(IStatController.ATTRIBUTES.DEXTERITY);
    indexes[2] = uint(IStatController.ATTRIBUTES.VITALITY);
    indexes[3] = uint(IStatController.ATTRIBUTES.ENERGY);
    indexes[4] = uint(IStatController.ATTRIBUTES.DAMAGE_MIN);
    indexes[5] = uint(IStatController.ATTRIBUTES.DAMAGE_MAX);
    indexes[6] = uint(IStatController.ATTRIBUTES.ATTACK_RATING);
    indexes[7] = uint(IStatController.ATTRIBUTES.DEFENSE);
    indexes[8] = uint(IStatController.ATTRIBUTES.BLOCK_RATING);
    indexes[9] = uint(IStatController.ATTRIBUTES.FIRE_RESISTANCE);
    indexes[10] = uint(IStatController.ATTRIBUTES.COLD_RESISTANCE);
    indexes[11] = uint(IStatController.ATTRIBUTES.LIGHTNING_RESISTANCE);

    return _generateReinforcementAttributes(sc, indexes, heroToken, heroTokenId);
  }

  /// @notice Claim all rewards from {_heroTokenRewards} to {recipient}, remove data from {_heroTokenRewards}
  function _claimAllTokenRewards(address heroToken, uint heroId, address recipient) internal {
    EnumerableMap.AddressToUintMap storage rewards = _S()._heroTokenRewards[heroToken.packNftId(heroId)];
    uint length = rewards.length();
    address[] memory tokens = new address[](length);
    for (uint i; i < length; ++i) {
      (address token, uint amount) = rewards.at(i);
      IERC20(token).transfer(recipient, amount);
      emit IApplicationEvents.ClaimedToken(heroToken, heroId, token, amount, recipient);

      tokens[i] = token;
    }

    // need to remove after the ordered reading for handle all elements, just remove the struct will not work coz contains mapping inside
    for (uint i; i < length; ++i) {
      rewards.remove(tokens[i]);
    }
  }

  function _claimAllNftRewards(address heroToken, uint heroId, address recipient) internal {
    bytes32[] storage rewards = _S()._heroNftRewards[heroToken.packNftId(heroId)];
    uint length = rewards.length;
    for (uint i; i < length; ++i) {
      (address token, uint id) = rewards[i].unpackNftId();
      IERC721(token).safeTransferFrom(address(this), recipient, id);
      emit IApplicationEvents.ClaimedItem(heroToken, heroId, token, id, recipient);
    }
    // a simple array can be just deleted
    delete _S()._heroNftRewards[heroToken.packNftId(heroId)];
  }

  /// @notice Claim last {countNft} NFTs and remove them from {_heroNftRewards}
  function _claimNftRewards(address heroToken, uint heroId, address recipient, uint countNft) internal {
    bytes32[] storage rewards = _S()._heroNftRewards[heroToken.packNftId(heroId)];

    uint length = rewards.length;
    uint indexLastToDelete = countNft >= length
      ? 0
      : length - countNft;

    while (length != indexLastToDelete) {
      (address token, uint id) = rewards[length - 1].unpackNftId();
      IERC721(token).safeTransferFrom(address(this), recipient, id);
      emit IApplicationEvents.ClaimedItem(heroToken, heroId, token, id, recipient);
      length--;

      // if we are going to remove all items we can just delete all items at the end
      // otherwise we should pop the items one by one
      if (indexLastToDelete != 0) {
        rewards.pop();
      }
    }

    if (length == 0) {
      delete _S()._heroNftRewards[heroToken.packNftId(heroId)];
    }
  }

  function _generateReinforcementAttributes(IStatController sc, uint[] memory indexes, address heroToken, uint heroId)
  internal view returns (int32[] memory attributes) {
    attributes = new int32[](uint(IStatController.ATTRIBUTES.END_SLOT));
    for (uint i; i < indexes.length; ++i) {
      attributes[indexes[i]] = CalcLib.max32(sc.heroAttribute(heroToken, heroId, indexes[i]) * _ATTRIBUTES_RATIO / 100, 1);
    }
  }
  //endregion ------------------------ Internal logic

  //region ------------------------ Fixed fee calculation V2

  /// @notice hitsLast24h Number of hits per last 24 hours, decimals 18
  function _getFeeAmount(address gameToken, uint hitsLast24h, uint8 biome) internal view returns (uint) {

    // get min-max range for the burn fee
    (uint32 minNumberHits, uint32 maxNumberHits, uint32 lowDivider, uint32 highDivider,) = getConfigV2();
    uint min = 1e18 * uint(minNumberHits);
    uint max = 1e18 * uint(maxNumberHits);

    // get max amount of the fee using original minter.amountForDungeon
    // we should pass heroBiome EXACTLY same to dungeonBiomeLevel
    // to avoid reducing base because of the difference heroBiome and dungeonBiomeLevel, see {amountForDungeon}
    IMinter minter = IMinter(IGameToken(gameToken).minter());
    uint amountForDungeon = minter.amountForDungeon(biome, biome) * 10;

    // calculate fee
    if (hitsLast24h < min) hitsLast24h = min;
    if (hitsLast24h > max) hitsLast24h = max;

    uint f = 1e18 * (hitsLast24h - min) / (max - min);
    return amountForDungeon / lowDivider + f * (amountForDungeon / highDivider - amountForDungeon / lowDivider) / 1e18;
  }

  /// @notice Process the next call of askHeroV2
  /// @return hitsLast24h Number of askHeroV2-calls for last 24 hours, decimals 18
  /// @return dest Updated last-24hours-window-statistics to be stored in the storage
  function getHitsNumberPerLast24Hours(
    uint blockTimestamp,
    uint basketInterval,
    IReinforcementController.LastWindowsV2 memory s
  ) internal pure returns (
    uint hitsLast24h,
    IReinforcementController.LastWindowsV2 memory dest
  ) {
    uint countBaskets = 24 / basketInterval;
    uint hour = blockTimestamp / 60 / 60;

    // get absolute index of basket for the current hour
    uint targetBasketIndex = hour / basketInterval;

    if (s.basketIndex == targetBasketIndex) {
      // current basket is not changed, increase the counter
      if (s.basketValue < type(uint24).max) {
        s.basketValue++;
      }
    } else {
      // current basket is changed
      // save value of previous basket to {baskets} and start counting from the zero
      s.baskets[s.basketIndex % countBaskets] = s.basketValue;

      // clear outdated baskets if some baskets were skipped (users didn't make any actions too long)
      if (targetBasketIndex >= s.basketIndex + countBaskets) {
        for (uint i; i < countBaskets; ++i) {
          s.baskets[i] = 0;
        }
      } else {
        for (uint i = s.basketIndex + 1; i < targetBasketIndex; ++i) {
          s.baskets[i % countBaskets] = 0;
        }
      }

      s.basketValue = 1;
      s.basketIndex = uint48(targetBasketIndex);
    }

    // calculate sum for last 24 hours
    uint m = 1e18 * (blockTimestamp - targetBasketIndex * basketInterval * 60 * 60) / (basketInterval * 60 * 60);
    uint bi = s.basketIndex % countBaskets;
    for (uint i; i < countBaskets; ++i) {
      if (i == bi) {
        hitsLast24h += uint(s.baskets[i]) * (1e18 - m) + m * uint(s.basketValue);
      } else {
        hitsLast24h += uint(s.baskets[i]) * 1e18;
      }
    }

    return (hitsLast24h, s);
  }
  //endregion ------------------------ Fixed fee calculation V2
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IGuildController.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IPvpController.sol";
import "../interfaces/IReinforcementController.sol";
import "../interfaces/IGuildStakingAdapter.sol";
import "./CalcLib.sol";
import "./ControllerContextLib.sol";
import "./ScoreLib.sol";
import "./MonsterLib.sol";
import "./AppLib.sol";
import "./PackingLib.sol";
import "./ReinforcementControllerLib.sol";

library PvpControllerLib {
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using EnumerableMap for EnumerableMap.UintToUintMap;

  //region ------------------------ Constants

  /// @dev keccak256(abi.encode(uint256(keccak256("pvp.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant PVP_CONTROLLER_STORAGE_LOCATION = 0x6750db0cf5db3c73c8abbeff54ef9c65daabbed6967cb68f37e0698f5fc7bb00;

  /// @notice First guild level starting from which the pvp-fights are allowed
  uint internal constant MIN_GUILD_LEVEL_REQUIRED_FOR_PVP = 3;

  /// @notice Fight-winner is allowed to make more pvp-fights in the same epoch
  bool internal constant MULTI_FIGHTS_PER_EPOCH_ALLOWED_FOR_WINNERS = true;

  /// @notice Hero can be pvp-staked if his level is greater of equal to the given min level
  uint32 internal constant DEFAULT_MIN_HERO_LEVEL = 5;

  /// @notice Max number of heroes that any user can pvp-stakes per single epoch
  /// @dev uint32 is used to be able to store max value inside UserState, -1 is for unit tests
  uint32 internal constant MAX_NUMBER_STAKES_FOR_USER_PER_EPOCH = type(uint32).max - 1;
  //endregion ------------------------ Constants

  //region ------------------------ Data types
  struct AddPvpHeroLocal {
    uint8 targetBiome;
    uint32 week;
    bytes32 packedHero;
    IGuildController guildController;
    IHeroController heroController;
    IStatController statController;
    address opponent;
    bytes32 opponentPackedHero;
    uint opponentGuildId;
    uint guildId;
    IPvpController.PvpUserState userState;
    SetupPvpFightParams eventParams;
  }

  struct SetupPvpFightParams {
    uint32 week;
    address hero;
    uint heroId;
    bytes32 opponentPackedHero;
  }

  //endregion ------------------------ Data types

  //region ------------------------ Storage

  function _S() internal pure returns (IPvpController.MainState storage s) {
    assembly {
      s.slot := PVP_CONTROLLER_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ Storage

  //region ------------------------ Restrictions
  function _onlyNotPaused(IController controller) internal view {
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
  }

  function _onlyGuildController(IController controller) internal view {
    if (controller.guildController() != msg.sender) revert IAppErrors.ErrorNotGuildController();
  }

  function _onlyDeployer(IController controller) internal view {
    if (!controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }

  function _onlyUserWithRegisteredPvpHeroWithoutFights(IPvpController.PvpUserState memory userState) internal pure {
    if (userState.biome == 0) revert IAppErrors.PvpHeroNotRegistered();
    if (userState.activeFightIndex1 != 0) revert IAppErrors.PvpHeroHasInitializedFight();
  }

  //endregion ------------------------ Restrictions

  //region ------------------------ View
  function getBiomeOwner(uint8 biome) internal view returns (uint guildId) {
    return _S().biomeState[biome].guildBiomeOwnerId;
  }

  function getStartedEpoch(uint8 biome) internal view returns (uint32 epochWeek) {
    return _S().biomeState[biome].startedEpochWeek;
  }

  function getDominationCounter(uint8 biome) internal view returns (uint16 dominationCounter) {
    return _S().biomeState[biome].dominationCounter;
  }

  /// @notice List of guilds that send domination request for the biome
  function getBiomeGuilds(uint8 biome, uint32 epochWeek) internal view returns (uint[] memory guildIds) {
    return _S().epochData[epochWeek].biomeGuilds[biome].values();
  }

  /// @return biome Biome where the guild is going to dominate in the given epoch
  function getDominationRequest(uint guildId, uint32 epochWeek) internal view returns (uint8 biome) {
    return _S().epochData[epochWeek].targetBiome[guildId];
  }

  function getGuildPoints(uint8 biome, uint32 epochWeek, uint guildId) internal view returns (uint) {
    (bool exist, uint countPoints) = _S().epochData[epochWeek].epochBiomeData[biome].guildPoints.tryGet(guildId);
    return exist ? countPoints : 0;
  }

  function getFreeUsers(uint8 biome, uint32 epochWeek, uint guildId) internal view returns (address[] memory) {
    return _S().epochData[epochWeek].epochBiomeData[biome].freeUsers[guildId].values();
  }

  function getPvpStrategy(uint8 biome, uint32 epochWeek, address hero, uint heroId) internal view returns (bytes memory) {
    return _S().epochData[epochWeek].epochBiomeData[biome].pvpStrategy[PackingLib.packNftId(hero, heroId)];
  }

  function getPvpStrategyKind(uint8 biome, uint32 epochWeek, address hero, uint heroId) internal view returns (uint) {
    return PackingLib.getPvpBehaviourStrategyKind(_S().epochData[epochWeek].epochBiomeData[biome].pvpStrategy[PackingLib.packNftId(hero, heroId)]);
  }

  function getFightDataLength(uint32 epochWeek, address user) internal view returns (uint) {
    return _S().epochData[epochWeek].fightData[user].length;
  }

  function getFightDataByIndex(uint32 epochWeek, address user, uint index0) internal view returns (IPvpController.PvpFightData memory) {
    return _S().epochData[epochWeek].fightData[user][index0];
  }

  function registeredUsers(uint8 biome, uint32 epochWeek, uint guildId) internal view returns (address[] memory) {
    return _S().epochData[epochWeek].epochBiomeData[biome].registeredHeroes[guildId].keys();
  }

  function registeredHero(uint8 biome, uint32 epochWeek, uint guildId, address user) internal view returns (address hero, uint heroId) {
    (bool exist, uint packedHero) = _S().epochData[epochWeek].epochBiomeData[biome].registeredHeroes[guildId].tryGet(user);
    if (exist) {
      (hero, heroId) = PackingLib.unpackNftId(bytes32(packedHero));
    }
    return (hero, heroId);
  }

  function ownedBiome(uint guildId) internal view returns (uint8 biome) {
    return _S().ownedBiome[guildId];
  }

  /// @notice Get biome tax
  /// @return guildId Owner of the biome
  /// @return taxPercent Final tax percent, [0...100_000], decimals 3
  function getBiomeTax(uint8 biome) internal view returns (uint guildId, uint taxPercent) {
    return _getBiomeTax(_S().biomeState[biome]);
  }

  /// @notice Check if the user has a pvp-hero registered for pvp-fight in the given epoch
  function hasPvpHero(address user, uint guildId, uint32 week) internal view returns (bool) {
    IPvpController.EpochData storage epochData = _S().epochData[week];
    uint8 biome = epochData.targetBiome[guildId];
    return biome == 0
      ? false
      : epochData.epochBiomeData[biome].registeredHeroes[guildId].contains(user);
  }

  /// @notice Check if the given hero is staked in pvp controller in the given epoch
  function isHeroStaked(address hero, uint heroId, uint32 epochWeek) internal view returns (bool staked) {
    IPvpController.EpochData storage epochData = _S().epochData[epochWeek];
    return epochData.stakedHeroes.contains(uint(PackingLib.packNftId(hero, heroId)));
  }

  function getUserState(uint32 week, address user) internal view returns (IPvpController.PvpUserState memory) {
    return _S().epochData[week].pvpUserState[user];
  }

  function getMinHeroLevel() internal view returns (uint) {
    return _S().pvpParam[IPvpController.PvpParams.MIN_HERO_LEVEL_1];
  }

  function getCounterFightId() internal view returns (uint48) {
    return uint48(_S().pvpParam[IPvpController.PvpParams.FIGHT_COUNTER_3]);
  }

  function getGuildStakingAdapter() internal view returns (address) {
    return address(uint160(_S().pvpParam[IPvpController.PvpParams.GUILD_STAKING_ADAPTER_2]));
  }

  //endregion ------------------------ View

  //region ------------------------ Deployer actions
  function setMinHeroLevel(IController controller, uint level) internal {
    _onlyDeployer(controller);

    _S().pvpParam[IPvpController.PvpParams.MIN_HERO_LEVEL_1] = level;
    emit IApplicationEvents.SetMinHeroLevel(level);
  }

  function setGuildStakingAdapter(IController controller, address adapter_) internal {
    _onlyDeployer(controller);

    _S().pvpParam[IPvpController.PvpParams.GUILD_STAKING_ADAPTER_2] = uint(uint160(adapter_));
    emit IApplicationEvents.SetGuildStakingAdapter(adapter_);
  }
  //endregion ------------------------ Deployer actions

  //region ------------------------ Domination actions

  /// @notice Create new request for domination. New request can be created once per epoch
  /// @param biome Biome selected by the guild for domination in the current epoch
  /// @param random_ CalcLib.pseudoRandom, required for unit tests
  function selectBiomeForDomination(
    address msgSender,
    IController controller,
    uint8 biome,
    uint blockTimestamp,
    function (uint) internal view returns (uint) random_
  ) internal {
    _onlyNotPaused(controller);
    IGuildController guildController = IGuildController(controller.guildController());

    if (biome == 0) revert IAppErrors.ErrorIncorrectBiome(biome);
    (uint guildId,) = _checkPermissions(guildController, msgSender, IGuildController.GuildRightBits.DOMINATION_REQUEST_13);

    {
      (,,, uint8 guildLevel,,) = guildController.getGuildData(guildId);
      if (guildLevel < MIN_GUILD_LEVEL_REQUIRED_FOR_PVP) revert IAppErrors.TooLowGuildLevel();
    }

    uint32 week = getCurrentEpochWeek(blockTimestamp);
    IPvpController.EpochData storage epochData = _S().epochData[week];

    if (epochData.targetBiome[guildId] != 0) revert IAppErrors.BiomeAlreadySelected();

    _updateEpoch(biome, blockTimestamp, random_);

    // register new domination request
    epochData.targetBiome[guildId] = biome;
    epochData.biomeGuilds[biome].add(guildId);

    emit IApplicationEvents.AddBiomeRequest(msgSender, biome, guildId, week);
  }

  /// @notice Register hero for pvp. User is able to register only one hero at any moment.
  /// @param random_ CalcLib.pseudoRandom, required for unit tests
  function addPvpHero(
    address msgSender,
    IController controller,
    address hero,
    uint heroId,
    bytes memory pvpStrategyData,
    uint8 maxFights,
    uint blockTimestamp,
    function (uint) internal view returns (uint) random_
  ) internal {
    _onlyNotPaused(controller);

    AddPvpHeroLocal memory v;
    v.guildController = IGuildController(controller.guildController());
    v.heroController = IHeroController(controller.heroController());
    v.statController = IStatController(controller.statController());
    v.week = getCurrentEpochWeek(blockTimestamp);

    // any guild member can participate in pvp, no permissions are required
    (v.guildId, v.targetBiome) = _getTargetDominationBiomeWithCheck(msgSender, v.guildController, v.week, true);

    if (IERC721(hero).ownerOf(heroId) != msgSender) revert IAppErrors.ErrorNotOwner(hero, heroId);
    if (v.heroController.heroClass(hero) == 0) revert IAppErrors.ErrorHeroIsNotRegistered(hero);
    if (IReinforcementController(controller.reinforcementController()).isStaked(hero, heroId)) revert IAppErrors.Staked(hero, heroId);
    if (!v.statController.isHeroAlive(hero, heroId)) revert IAppErrors.ErrorHeroIsDead(hero, heroId);
    if (v.heroController.sandboxMode(hero, heroId) == uint8(IHeroController.SandboxMode.SANDBOX_MODE_1)) revert IAppErrors.SandboxModeNotAllowed();
    if (IDungeonFactory(controller.dungeonFactory()).currentDungeon(hero, heroId) != 0) revert IAppErrors.HeroInDungeon();
    if (v.heroController.countHeroTransfers(hero, heroId) > 1) revert IAppErrors.HeroWasTransferredBetweenAccounts();

    // assume here that there is no reason to check guild level - it's high enough as soon as targetBiome != 0

    {
      uint32 heroLevel = v.statController.heroStats(hero, heroId).level;
      if (heroLevel < getMinHeroLevel()) revert IAppErrors.ErrorLevelTooLow(heroLevel);
    }

    _updateEpoch(v.targetBiome, blockTimestamp, random_);

    // check current fight status
    IPvpController.EpochData storage epochData = _S().epochData[v.week];
    v.userState = epochData.pvpUserState[msgSender];

    if (v.userState.biome != 0) revert IAppErrors.UserHasRegisteredPvpHeroInBiome(v.userState.biome);
    if (v.userState.numHeroesStaked >= MAX_NUMBER_STAKES_FOR_USER_PER_EPOCH) revert IAppErrors.UserNotAllowedForPvpInCurrentEpoch(v.week);

    // register new hero
    IPvpController.EpochBiomeData storage epochBiomeData = epochData.epochBiomeData[v.targetBiome];
    v.packedHero = PackingLib.packNftId(hero, heroId);

    { // attackInfo params are NOT validated here, they will be checked just before using
      uint pvpStrategyKind = PackingLib.getPvpBehaviourStrategyKind(pvpStrategyData);
      if (pvpStrategyKind != uint(IPvpController.PvpBehaviourStrategyKinds.DEFAULT_STRATEGY_0)) revert IAppErrors.UnknownPvpStrategy();
      epochBiomeData.pvpStrategy[v.packedHero] = pvpStrategyData;
    }

    epochBiomeData.registeredHeroes[v.guildId].set(msgSender, uint(v.packedHero));
    epochData.stakedHeroes.add(uint(v.packedHero));

    // initialize new user state
    epochData.pvpUserState[msgSender] = IPvpController.PvpUserState({
      biome: v.targetBiome,
      guildId: uint64(v.guildId),
      activeFightIndex1: 0,  // there is no active fight at this moment
      numHeroesStaked: 1 + v.userState.numHeroesStaked,
      countFights: 0,
      maxFights: maxFights,
      fightId: 0  // there is no active fight at this moment
    });

    // emit PvpHeroAdded before emitting of PreparePvpFight
    emit IApplicationEvents.PvpHeroAdded(msgSender, v.guildId, hero, heroId, v.week, v.targetBiome);

    // try to find opponent for the newly registered hero and initialize the fight if an opponent is found
    (v.opponent, v.opponentPackedHero, v.opponentGuildId) = _findPvpOpponent(v.guildController, v.targetBiome, epochData, v.guildId, random_);
    if (v.opponent == address(0)) {
      epochBiomeData.freeUsers[v.guildId].add(msgSender);
    } else {
      v.eventParams = SetupPvpFightParams({
        week: v.week,
        hero: hero,
        heroId: heroId,
        opponentPackedHero: v.opponentPackedHero
      });
      _setupPvpFight(v.targetBiome, epochData, msgSender, v.opponent, v.guildId, v.opponentGuildId, v.eventParams);
    }
  }

  /// @notice Remove pvp-hero registered by the {msgSender}.
  /// It's allowed only if pvp-hero has no initialized fight.
  function removePvpHero(address msgSender, IController controller, uint blockTimestamp) internal {
    _onlyNotPaused(controller);

    uint32 week = getCurrentEpochWeek(blockTimestamp);

    IPvpController.EpochData storage epochData = _S().epochData[week];
    IPvpController.PvpUserState memory userState = epochData.pvpUserState[msgSender];
    _onlyUserWithRegisteredPvpHeroWithoutFights(userState);

    IPvpController.EpochBiomeData storage epochBiomeData = epochData.epochBiomeData[userState.biome];
    _removePvpHero(week, epochData, epochBiomeData, userState, msgSender, true);
  }

  /// @param manualRemoving True if the hero is remove manually by the user, false - he is removed automatically after the fight
  function _removePvpHero(
    uint32 week,
    IPvpController.EpochData storage epochData,
    IPvpController.EpochBiomeData storage epochBiomeData,
    IPvpController.PvpUserState memory userState,
    address user,
    bool manualRemoving
  ) internal {
    address hero;
    uint heroId;
    (bool exist, uint packedHeroAsUint) = epochBiomeData.registeredHeroes[userState.guildId].tryGet(user);
    if (exist) {
      epochBiomeData.registeredHeroes[userState.guildId].remove(user);
      epochData.stakedHeroes.remove(packedHeroAsUint);
      (hero, heroId) = PackingLib.unpackNftId(bytes32(packedHeroAsUint));
    }
    epochBiomeData.freeUsers[userState.guildId].remove(user);

    epochData.pvpUserState[user] = IPvpController.PvpUserState({
      activeFightIndex1: 0,
      biome: 0,
      guildId: 0,
      numHeroesStaked: userState.numHeroesStaked,
      countFights: 0,
      maxFights: 0,
      fightId: 0
    });

    emit IApplicationEvents.PvpHeroRemoved(user, userState.guildId, week, userState.biome, hero, heroId, manualRemoving);
  }


  /// @notice Change epoch if the current epoch is completed, update biome owner
  /// @param random_ CalcLib.pseudoRandom, required for unit tests
  function updateEpoch(
    uint8 biome,
    uint blockTimestamp,
    function (uint) internal view returns (uint) random_
  ) internal {
    // no restrictions to call

    _updateEpoch(biome, blockTimestamp, random_);
  }

  /// @notice Update epoch if necessary and get biome tax that takes into current biome owner
  /// @return guildId Owner of the biome
  /// @return taxPercent Tax percent in favor of the biome owner. [0...100_000], decimals 3
  function refreshBiomeTax(
    uint8 biome,
    uint blockTimestamp,
    function (uint) internal view returns (uint) random_
  ) internal returns (uint guildId, uint taxPercent) {
    // no restrictions to call though this method is intended to be called by DungeonFactory
    IPvpController.BiomeData memory biomeData = _updateEpoch(biome, blockTimestamp, random_);
    return _getBiomeTax(biomeData);
  }

  /// @notice Called by GuildController when the guild is deleted
  function onGuildDeletion(IController controller, uint guildId) internal {
    _onlyGuildController(controller);

    IPvpController.EpochData storage epochData = _S().epochData[getCurrentEpochWeek(block.timestamp)];
    uint8 targetBiome = epochData.targetBiome[guildId];
    if (targetBiome != 0) {
      // deleted guild cannot be selected for new fights anymore
      epochData.biomeGuilds[targetBiome].remove(guildId);
    }

    // deleted guild cannot own a biome anymore
    uint8 _ownedBiome = _S().ownedBiome[guildId];
    if (_ownedBiome != 0) {
      delete _S().ownedBiome[guildId];
      delete _S().biomeState[_ownedBiome];
    }
  }
  //endregion ------------------------ Domination actions

  //region ------------------------ Domination internal

  /// @notice Finalize passed epoch, initialize first epoch.
  /// Detect a winner for biome if it's not detected yet.
  function _updateEpoch(
    uint8 biome,
    uint blockTimestamp,
    function (uint) internal view returns (uint) random_
  ) internal returns (IPvpController.BiomeData memory biomeData) {
    biomeData = _S().biomeState[biome];
    uint32 week = getCurrentEpochWeek(blockTimestamp);
    if (biomeData.startedEpochWeek == 0) {
      // initialize first epoch
      biomeData.startedEpochWeek = week;
      _S().biomeState[biome] = biomeData;
      emit IApplicationEvents.FirstPvpEpoch(biome, week);
    } else {
      if (week != biomeData.startedEpochWeek) {
        // started epoch has passed, it's time to sum up the results
        uint[] memory guildIds = _S().epochData[biomeData.startedEpochWeek].biomeGuilds[biome].values();

        // detect new biome owner
        uint guildBiomeOwnerId = _detectBiomeOwner(biome, biomeData.startedEpochWeek, guildIds, random_);

        if (guildBiomeOwnerId == 0) {
          // new biome owner is not detected .. keep previous one
          guildBiomeOwnerId = biomeData.guildBiomeOwnerId;
        }

        if (guildBiomeOwnerId != biomeData.guildBiomeOwnerId) {
          uint8 prevBiome = _S().ownedBiome[guildBiomeOwnerId];

          // clear data for prev owner of the biome
          if (biomeData.guildBiomeOwnerId != 0) {
            delete _S().ownedBiome[biomeData.guildBiomeOwnerId];
          }

          // clear previously owned biome
          if (prevBiome != 0) {
            _S().biomeState[prevBiome].guildBiomeOwnerId = 0;
            _S().biomeState[prevBiome].dominationCounter = 0;
          }

        // update ownedBiome
          _S().ownedBiome[guildBiomeOwnerId] = biome;
        }

        // update biome state
        biomeData = IPvpController.BiomeData({
          guildBiomeOwnerId: uint64(guildBiomeOwnerId),
          startedEpochWeek: week,
          dominationCounter: guildBiomeOwnerId == biomeData.guildBiomeOwnerId && guildBiomeOwnerId != 0
            ? biomeData.dominationCounter + uint16(week - biomeData.startedEpochWeek) // penalty for repeat domination
            : 0
        });
        _S().biomeState[biome] = biomeData;

        emit IApplicationEvents.UpdatePvpEpoch(biome, week, guildBiomeOwnerId);
      }
    }
  }

  /// @notice Select a winner - the guild with max number of points
  /// If several guilds have same number of points, the winner is selected randomly
  /// @param random_ CalcLib.pseudoRandom, required for unit tests
  /// @return guildBiomeOwnerId New guild biome owner. If new biome owner is not detected, prev biome owner is returned
  function _detectBiomeOwner(
    uint8 biome,
    uint week,
    uint[] memory guildIds,
    function (uint) internal view returns (uint) random_
  ) internal view returns (uint guildBiomeOwnerId) {

    uint len = guildIds.length;
    uint[] memory guildPoints = new uint[](len);

    uint selectedIndexP1; // 1-based index of the first winner guild in {guildPoints}
    uint countWinners; // total count of winners - the guilds with equal max number of points

    // find all winners - the guilds with max number of points
    IPvpController.EpochBiomeData storage epochBiomeData = _S().epochData[week].epochBiomeData[biome];
    for (uint i; i < len; ++i) {
      (bool exist, uint countPoints) = epochBiomeData.guildPoints.tryGet(guildIds[i]);
      if (exist && countPoints != 0) {
        guildPoints[i] = countPoints;
        if (selectedIndexP1 == 0 || guildPoints[selectedIndexP1 - 1] < countPoints) {
          selectedIndexP1 = i + 1;
          countWinners = 1;
        } else if (guildPoints[selectedIndexP1 - 1] == countPoints) {
          countWinners++;
        }
      }
    }

    // select random winner from all potential winners
    if (selectedIndexP1 != 0) {
      uint indexWinner = countWinners == 1 ? 0 : random_(countWinners - 1);
      if (indexWinner == 0) {
        guildBiomeOwnerId = guildIds[selectedIndexP1 - 1];
      } else {
        for (uint i = selectedIndexP1; i < len; ++i) {
          if (guildPoints[i] == guildPoints[selectedIndexP1 - 1]) {
            if (indexWinner == 1) {
              guildBiomeOwnerId = guildIds[i];
              break;
            } else {
              indexWinner--;
            }
          }
        }
      }
    }

    return guildBiomeOwnerId;
  }

  /// @notice Try to find pvp-opponent for the hero.
  /// @param heroGuildId Guild of the hero
  /// @param random_ CalcLib.pseudoRandom, required for unit tests
  function _findPvpOpponent(
    IGuildController guildController,
    uint8 biome,
    IPvpController.EpochData storage epochData,
    uint heroGuildId,
    function (uint) internal view returns (uint) random_
  ) internal view returns (
    address opponentUser,
    bytes32 opponentPackedHero,
    uint opponentGuildId
  ) {
    (,,,uint8 guildLevel,,) = guildController.getGuildData(heroGuildId);
    if (guildLevel >= MIN_GUILD_LEVEL_REQUIRED_FOR_PVP) {
      IPvpController.EpochBiomeData storage epochBiomeData = epochData.epochBiomeData[biome];
      opponentGuildId = _selectPvpOpponentGuild(guildController, epochData.biomeGuilds[biome], epochBiomeData, heroGuildId, random_);
      if (opponentGuildId != 0) {
        (opponentUser, opponentPackedHero) = _selectPvpOpponent(epochBiomeData, opponentGuildId, random_);
        if (opponentPackedHero == 0) revert IAppErrors.ZeroAddress();

        // Pvp-fight is initialized, but not started
        // One of the users should start the fight manually
      }
    }

    return (opponentUser, opponentPackedHero, opponentGuildId);
  }

  /// @notice Prepare the fight: hero vs opponent.
  /// Both the hero and his opponent are prepared to the fight in result, but the fight is not started.
  /// @param heroOwner Owner of the selected hero
  function _setupPvpFight(
    uint8 biome,
    IPvpController.EpochData storage epochData,
    address heroOwner,
    address opponentUser,
    uint heroGuildId,
    uint opponentGuildId,
    SetupPvpFightParams memory eventParams
  ) internal {
    // Set up the fight between the hero and his opponent
    epochData.fightData[heroOwner].push(IPvpController.PvpFightData({
      fightOpponent: opponentUser,
      fightStatus: IPvpController.PvpFightStatus.PREPARED_1,
      health: 0,
      countTurns: 0,
      mana: 0
    }));

    epochData.fightData[opponentUser].push(IPvpController.PvpFightData({
      fightOpponent: heroOwner,
      fightStatus: IPvpController.PvpFightStatus.PREPARED_1,
      health: 0,
      countTurns: 0,
      mana: 0
    }));

    // update users states
    uint48 fightId = _generateFightId();
    epochData.pvpUserState[heroOwner].activeFightIndex1 = uint32(epochData.fightData[heroOwner].length);
    epochData.pvpUserState[heroOwner].fightId = fightId;

    epochData.pvpUserState[opponentUser].activeFightIndex1 = uint32(epochData.fightData[opponentUser].length);
    epochData.pvpUserState[opponentUser].fightId = fightId;

    // remove free users (assume, that remove doesn't revert if user is not there)
    epochData.epochBiomeData[biome].freeUsers[heroGuildId].remove(heroOwner);
    epochData.epochBiomeData[biome].freeUsers[opponentGuildId].remove(opponentUser);

    (address opponentHero, uint opponentHeroId) = PackingLib.unpackNftId(bytes32(eventParams.opponentPackedHero));
    emit IApplicationEvents.PreparePvpFight(
      fightId,
      eventParams.week,
      eventParams.hero, eventParams.heroId, heroGuildId,
      opponentHero, opponentHeroId, opponentGuildId
    );
  }

  /// @notice Select random guild suitable to select pvp-opponent.
  /// The guild should have at least 1 free hero. The guild should have enough level.
  /// Relation between the guilds of the selected opponents should be "war".
  /// The opponents should belong to the different guilds.
  function _selectPvpOpponentGuild(
    IGuildController guildController,
    EnumerableSet.UintSet storage biomeGuilds,
    IPvpController.EpochBiomeData storage epochBiomeData,
    uint heroGuildId,
    function (uint) internal view returns (uint) random_
  ) internal view returns (uint resultGuildId) {
    // select first guild randomly
    // enumerate all guilds one by one (loop) and find first guild with available free hero
    uint len = biomeGuilds.length();

    // biomeGuilds should have at least two guild: hero's guild and opponent's guild
    // if there is only 1 guild it means that this is hero's guild and no opponent is available
    if (len > 1) {
      uint index0 = random_(len - 1);
      uint index = index0;
      while (true) {
        uint guildId = biomeGuilds.at(index);
        (,,,uint8 guildLevel,,) = guildController.getGuildData(guildId);

        if (guildLevel >= MIN_GUILD_LEVEL_REQUIRED_FOR_PVP
        && epochBiomeData.freeUsers[guildId].length() != 0
        && heroGuildId != guildId
          && !guildController.isPeacefulRelation(heroGuildId, guildId)
        ) {
          resultGuildId = guildId;
          break;
        }

        index = index + 1 == len ? 0 : index + 1; // loop
        if (index == index0) {
          // guild wasn't found
          break;
        }
      }
    }

    return resultGuildId;
  }

  /// @notice Select random pvp-opponent in the given {guild}
  function _selectPvpOpponent(
    IPvpController.EpochBiomeData storage epochBiomeData,
    uint guildId,
    function (uint) internal view returns (uint) random_
  ) internal view returns (address user, bytes32 packedHero) {
    EnumerableSet.AddressSet storage freeUsers = epochBiomeData.freeUsers[guildId];
    uint len = freeUsers.length();
    if (len != 0) {
      uint index = len == 1 ? 0 : random_(len - 1);
      user = freeUsers.at(index);
      packedHero = bytes32(epochBiomeData.registeredHeroes[guildId].get(user));
    }

    return (user, packedHero);
  }

  /// @return guildId Guild to which {msgSender} belongs, revert if 0
  /// @return targetBiome Domination biome of the guild, revert if 0
  function _getTargetDominationBiomeWithCheck(address msgSender, IGuildController guildController, uint32 week, bool revertOnZero) internal view returns (
    uint guildId,
    uint8 targetBiome
  ) {
    guildId = guildController.memberOf(msgSender);
    if (revertOnZero && guildId == 0) revert IAppErrors.NotGuildMember();

    targetBiome = guildId == 0
      ? 0
      : _S().epochData[week].targetBiome[guildId];
    if (revertOnZero && targetBiome == 0) revert IAppErrors.NoDominationRequest();
  }

  /// @notice Get biome tax that takes into account extra fee ratio provided by GuildStakingAdapter
  /// @return guildId Owner of the biome
  /// @return taxPercent Final tax percent that takes into account possible penalty. [0...100_000], decimals 3
  function _getBiomeTax(IPvpController.BiomeData memory biomeData) internal view returns (uint guildId, uint taxPercent) {
    guildId = biomeData.guildBiomeOwnerId;
    taxPercent = guildId == 0 ? 0 : AppLib.BIOME_TAX_PERCENT_MIN;

    if (guildId != 0) {
      // increment tax value depending on the liquidity amount staked by the guild
      address guildStakingAdapter = address(uint160(_S().pvpParam[IPvpController.PvpParams.GUILD_STAKING_ADAPTER_2]));
      if (guildStakingAdapter != address(0)) {

        // staked amount in game token
        uint extraFeeRatio = IGuildStakingAdapter(guildStakingAdapter).getExtraFeeRatio(guildId);

        taxPercent += (AppLib.BIOME_TAX_PERCENT_MAX - AppLib.BIOME_TAX_PERCENT_MIN) * Math.min(extraFeeRatio, 1e18) / 1e18;
      }
    }
  }

  //endregion ------------------------ Domination internal

  //region ------------------------ Utils
  function getCurrentEpochWeek(uint blockTimestamp) internal pure returns (uint32) {
    return _getEpochWeek(uint32(blockTimestamp / 86400));
  }

  /// @notice Calculate week for the given day. Assume that first day of the week is Monday
  function _getEpochWeek(uint epochDay) internal pure returns (uint32) {
    return uint32((epochDay + 3) / 7); // + 3 to move start of the first week to Monday 1969-12-29
  }

  /// @notice Check if the {user} has given permission in the guild. Permissions are specified by bitmask {rights}.
  /// Admin is marked by zero bit, he has all permissions always.
  function _checkPermissions(IGuildController guildController, address user, IGuildController.GuildRightBits right) internal view returns (uint guildId, uint rights) {
    guildId = guildController.memberOf(user);
    rights = guildController.getRights(user);

    if (guildId == 0) revert IAppErrors.NotGuildMember();

    if (!(
      (rights & (2 ** uint(IGuildController.GuildRightBits.ADMIN_0))) != 0
      || (rights & (2 ** uint(right))) != 0
    )) {
      revert IAppErrors.GuildActionForbidden(uint(right));
    }
  }

  function _getPointsWithPenalty(uint points_, uint dominationCounter) internal pure returns (uint) {
    uint penalty;
    if (dominationCounter != 0) {
      if (dominationCounter == 1) penalty = 10;
      else if (dominationCounter == 2) penalty = 25;
      else if (dominationCounter == 3) penalty = 38;
      else if (dominationCounter == 4) penalty = 50;
      else if (dominationCounter == 5) penalty = 61;
      else if (dominationCounter == 6) penalty = 70;
      else if (dominationCounter == 7) penalty = 78;
      else if (dominationCounter == 8) penalty = 84;
      else if (dominationCounter == 9) penalty = 89;
      else if (dominationCounter == 10) penalty = 93;
      else if (dominationCounter == 11) penalty = 96;
      else penalty = 98;
    }

    return points_ * (100 - penalty) / 100;
  }

  /// @notice Generate unique id of the pvp-fight (each pvp-fight consists from multiple turns)
  function _generateFightId() internal returns (uint48 fightId) {
    fightId = 1 + uint48(_S().pvpParam[IPvpController.PvpParams.FIGHT_COUNTER_3]);
    _S().pvpParam[IPvpController.PvpParams.FIGHT_COUNTER_3] = fightId;
  }
  //endregion ------------------------ Utils
}
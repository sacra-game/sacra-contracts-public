// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IUserController.sol";
import "../lib/StringLib.sol";
import "../solady/DateTimeLib.sol";
import "./ItemLib.sol";

library UserControllerLib {
  using EnumerableSet for EnumerableSet.Bytes32Set;

  //region ------------------------ Constants
  /// @dev keccak256(abi.encode(uint256(keccak256("user.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant USER_CONTROLLER_STORAGE_LOCATION = 0xb1ab856820591f650019ba94531c31db134c614288dc690130c9f2a4ef554800;
  /// @notice User should pass 3 dungeons to complete daily activity
  uint internal constant DAILY_ACTIVITY_DUNGEONS_THRESHOLD = 3;
  /// @notice User should make 1 pvp-fight to complete daily activity
  uint internal constant DAILY_ACTIVITY_PVP_THRESHOLD = 1;
  /// @notice Count of completed daily activities required to complete weekly activity
  uint internal constant WEEKLY_ACTIVITY_THRESHOLD = 7;
  /// @notice Default value of renaming fee, in game token, decimals 18
  uint internal constant FEE_RENAMING_DEFAULT_VALUE = 1000e18;
  /// @notice The number of game points by which the balance of the user increases after completing a dungeon
  uint internal constant GAME_POINTS_INC = 10;

  uint internal constant DAILY_ACTIVITY_THRESHOLD_INDEX = 0;
  uint internal constant WEEKLY_ACTIVITY_THRESHOLD_INDEX = 1;
  uint internal constant DAILY_ACTIVITY_PVP_THRESHOLD_INDEX = 2;

  //endregion ------------------------ Constants

  //region ------------------------ Restrictions
  function _onlyEoa(bool isEoa) internal pure {
    if (!isEoa) revert IAppErrors.ErrorOnlyEoa();
  }

  function _onlyDungeonFactory(IController controller, address msgSender) internal view {
    if (controller.dungeonFactory() != msgSender) revert IAppErrors.ErrorNotDungeonFactory(msgSender);
  }

  function _onlyGOC(IController controller, address msgSender) internal view {
    if (controller.gameObjectController() != msgSender) revert IAppErrors.ErrorNotGoc();
  }

  function _onlyPvpController(IController controller, address msgSender) internal view {
    if (controller.pvpController() != msgSender) revert IAppErrors.NotPvpController();
  }

  function _onlyHeroController(IController controller, address msgSender) internal view {
    if (controller.heroController() != msgSender) revert IAppErrors.ErrorNotHeroController(msgSender);
  }

  function _onlyGovernance(IController controller, address msgSender) internal view {
    if (controller.governance() != msgSender) revert IAppErrors.NotGovernance(msgSender);
  }

  function _onlyDeployer(IController controller, address msgSender) internal view {
    if (!controller.isDeployer(msgSender)) revert IAppErrors.ErrorNotDeployer(msgSender);
  }

  function _onlyNotPaused(IController controller) internal view {
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
  }

  //endregion ------------------------ Restrictions

  //region ------------------------ Storage

  function _S() internal pure returns (IUserController.MainState storage s) {
    assembly {
      s.slot := USER_CONTROLLER_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ Storage

  //region ------------------------ View
  function getUserAccountName(address user) internal view returns (string memory) {
    return _S().userAccountName[user];
  }

  function getUserAvatar(address user) internal view returns (string memory) {
    return _S().userAvatar[user];
  }

  function nameToUserAccount(string memory name) internal view returns (address) {
    return _S().nameToUserAccount[name];
  }

  function getUserActivity(address user) internal view returns (IUserController.UserActivity memory) {
    return _S().userActivity[user];
  }

  function getCounterLootBoxes(address user) internal view returns (uint32 dailyCounter, uint32 weeklyCounter) {
    IUserController.EarnedLootBoxes memory data = _S().counterLootBoxes[user];
    return (data.dailyCounter, data.weeklyCounter);
  }

  function getLootBoxConfig(uint lootBoxKind) internal view returns (
    address[] memory mintItems,
    uint32[] memory mintItemsChances,
    uint maxDropItems
  ) {
    IUserController.LootBoxConfig memory config = _S().lootBoxConfig[IUserController.LootBoxKind(lootBoxKind)];
    return (config.mintItems, config.mintItemsChances, config.maxDropItems);
  }

  function getFeeRenaming() internal view returns (uint) {
    return _S().feeRenaming;
  }

  function fameHallHero(uint8 openedNgLevel) internal view returns (address hero, uint heroId, address heroOwner, uint64 tsOpen) {
    IUserController.FameHallData memory data = _S().fameHall[openedNgLevel];
    return (data.hero, data.heroId, data.heroOwner, data.tsOpen);
  }

  function gamePoints(address user) internal view returns (uint countGamePoints) {
    return _S().gamePoints[user];
  }

  function isStoryPassed(address user, uint16 storyId) internal view returns (bool) {
    return _S().passedObjects[user].contains(_getStoryIdHash(storyId));
  }

  function priceStorySkipping() internal view returns (uint) {
    return _S().userControllerParams[IUserController.UserControllerParam.PRICE_STORY_SKIPPING_1];
  }
  //endregion ------------------------ View

  //region ------------------------ ACTIONS
  /// @notice Set name of user account (free) or rename user account (feeRenaming is paid)
  function setUserName(bool isEoa, IController controller, address msgSender, string memory userAccountName) internal {
    _onlyEoa(isEoa);
    _onlyNotPaused(controller);

    if (_S().nameToUserAccount[userAccountName] != address(0)) revert IAppErrors.NameTaken();
    if (bytes(userAccountName).length >= 20) revert IAppErrors.TooBigName();
    if (!StringLib.isASCIILettersOnly(userAccountName)) revert IAppErrors.WrongSymbolsInTheName();

    // Empty name means that user hasn't assigned name yet. First assignment is free, renaming is paid.
    if (bytes(userAccountName).length == 0) revert IAppErrors.EmptyNameNotAllowed();
    string memory oldName = _S().userAccountName[msgSender];
    if (bytes(oldName).length != 0) {
      uint feeRenaming = _S().feeRenaming;
      if (feeRenaming != 0) {
        address token = controller.gameToken();
        controller.process(token, feeRenaming, msgSender);
      }
      delete _S().nameToUserAccount[oldName];
    }

    _S().userAccountName[msgSender] = userAccountName;
    _S().nameToUserAccount[userAccountName] = msgSender;

    emit IApplicationEvents.SetUserName(msgSender, userAccountName);
  }

  /// @notice Set avatar of user account (free)
  function setUserAvatar(bool isEoa, IController controller, address msgSender, string memory newUserAvatar) internal {
    _onlyEoa(isEoa);
    _onlyNotPaused(controller);

    if (bytes(newUserAvatar).length >= 256) revert IAppErrors.TooLongUrl();
    _S().userAvatar[msgSender] = newUserAvatar;
    emit IApplicationEvents.SetUserAvatar(msgSender, newUserAvatar);
  }

  /// @notice Use either daily or weekly loot box depending on value of {lootBoxKind}
  /// @param msgSender EOA
  /// @param nextPrng_ CalcLib.nextPrng or test routine
  /// @param mintRandomItems_ ItemLib._mintRandomItems or test routine
  function openLootBox(
    IController controller,
    address msgSender,
    IUserController.LootBoxKind lootBoxKind,
    function (LibPRNG.PRNG memory, uint) internal view returns (uint) nextPrng_,
    function (
      ItemLib.MintItemInfo memory,
      function (LibPRNG.PRNG memory, uint) internal view returns (uint)
    ) internal returns (address[] memory) mintRandomItems_
  ) internal {
    _onlyNotPaused(controller);

    IUserController.EarnedLootBoxes memory data = _S().counterLootBoxes[msgSender];
    if (
      (lootBoxKind == IUserController.LootBoxKind.WEEKLY_1 && data.weeklyCounter == 0)
      || (lootBoxKind == IUserController.LootBoxKind.DAILY_0 && data.dailyCounter == 0)
      || (lootBoxKind >= IUserController.LootBoxKind.END_SLOT)
    ) {
      revert IAppErrors.NoAvailableLootBox(msgSender, uint(lootBoxKind));
    }

    // apply daily/weekly loot box
    IUserController.LootBoxConfig memory config = _S().lootBoxConfig[lootBoxKind];
    address[] memory mintItems = mintRandomItems_(
      ItemLib.MintItemInfo({
        seed: 0,
        oracle: IOracle(controller.oracle()),

        mintItems: config.mintItems,
        mintItemsChances: config.mintItemsChances,
        maxItems: uint8(config.maxDropItems),

        amplifier: 0, // don't increase chances
        magicFind: 0, // don't increase chances
        destroyItems: 0, // don't reduce chances
        mintDropChanceDelta: 0 // don't reduce chances
      }),
      nextPrng_
    );

    // mint dropped items if any
    uint[] memory itemTokenIds;

    uint len = mintItems.length;
    if (len != 0) {
      IItemController ic = IItemController(controller.itemController());
      itemTokenIds = new uint[](len);

      // mint items to the user
      for (uint i; i < len; ++i) {
        itemTokenIds[i] = ic.mint(mintItems[i], msgSender, 0);
      }
    }

    // reduce the counter of available loot boxes
    if (lootBoxKind == IUserController.LootBoxKind.WEEKLY_1) {
      data.weeklyCounter--;
    } else {
      data.dailyCounter--;
    }

    _S().counterLootBoxes[msgSender] = data;

    emit IApplicationEvents.LootBoxOpened(msgSender, uint(lootBoxKind), mintItems, itemTokenIds);
  }
  //endregion ------------------------ ACTIONS

  //region ------------------------ Deployer actions
  function setLootBoxConfig(IController controller, address msgSender, uint lootBoxKind, IUserController.LootBoxConfig memory config) internal {
    _onlyDeployer(controller, msgSender);

    _S().lootBoxConfig[IUserController.LootBoxKind(lootBoxKind)] = config;
    emit IApplicationEvents.LootBoxConfigChanged(lootBoxKind, config.mintItems, config.mintItemsChances, config.maxDropItems);
  }

  /// @notice Set fee for renaming user accounts. Game token, value 0 is allowed.
  function setFeeRenaming(IController controller, address msgSender, uint feeRenaming) internal {
    _onlyGovernance(controller, msgSender);
    _S().feeRenaming = feeRenaming;

    emit IApplicationEvents.SetFeeRenaming(feeRenaming);
  }

  function setPriceStorySkipping(IController controller, address msgSender, uint priceInGamePoints) internal {
    _setParam(controller, msgSender, IUserController.UserControllerParam.PRICE_STORY_SKIPPING_1, priceInGamePoints);
  }
  //endregion ------------------------ Deployer actions

  //region ------------------------ IUserController
  /// @notice Register daily activity - a dungeon was passed. Increment balance of the game points.
  /// @param user Owner of the hero who has passed the dungeon
  /// @param msgSender Dungeon factory only
  /// @param user EOA
  /// @param blockTimestamp block.timestamp (param is used for test purposes)
  function registerPassedDungeon(
    IController controller,
    address msgSender,
    address user,
    uint blockTimestamp,
    uint[3] memory thresholds
  ) internal {
    _onlyDungeonFactory(controller, msgSender);

    _registerActivity(user, blockTimestamp, thresholds, false);

    uint balanceGamePoints = _S().gamePoints[user] + GAME_POINTS_INC;
    _S().gamePoints[user] = balanceGamePoints;

    emit IApplicationEvents.AddGamePoints(user, balanceGamePoints);
  }

  /// @notice Register daily activity - PvP was made
  /// @param user Owner of the hero who has taken participation in the PvP
  function registerPvP(
    IController controller,
    address msgSender,
    address user,
    uint blockTimestamp,
    uint[3] memory thresholds,
    bool /* isWinner */
  ) internal {
    _onlyPvpController(controller, msgSender);

    _registerActivity(user, blockTimestamp, thresholds, true);
  }

  /// @notice Register any daily activity - a dungeon was passed OR pvp-fight was made
  /// @param user Owner of the hero who has passed the dungeon
  /// @param user EOA
  /// @param blockTimestamp block.timestamp (param is used for test purposes)
  /// @param thresholds [dailyActivityThreshold, weeklyActivityThreshold, dailyActivityPvpThreshold], for tests
  /// @param pvp true if pvp-fight was made
  function _registerActivity(
    address user,
    uint blockTimestamp,
    uint[3] memory thresholds,
    bool pvp
  ) internal {
    IUserController.UserActivity memory userActivity = _S().userActivity[user];
    uint32 epochDay = uint32(blockTimestamp / 86400);
    if (epochDay != userActivity.epochDay) {
      userActivity.epochDay = epochDay;
      userActivity.counterPassedDungeons = 0;
      userActivity.counterPvp = 0;
      userActivity.dailyLootBoxReceived = false;
    }

    uint32 epochWeek = getEpochWeek(epochDay);
    if (epochWeek != userActivity.epochWeek) {
      userActivity.weeklyLootBoxReceived = false;
      userActivity.dailyActivities = 0;
      userActivity.epochWeek = 0;
    }

    if (pvp) {
      userActivity.counterPvp += 1;
      emit IApplicationEvents.RegisterPvp(user, epochWeek, userActivity.counterPvp);
    } else {
      userActivity.counterPassedDungeons += 1;
      emit IApplicationEvents.RegisterPassedDungeon(user, epochWeek, userActivity.counterPassedDungeons);
    }

    if (!userActivity.dailyLootBoxReceived) {
      if (
        (userActivity.counterPassedDungeons >= thresholds[DAILY_ACTIVITY_THRESHOLD_INDEX])
        && (userActivity.counterPvp >= thresholds[DAILY_ACTIVITY_PVP_THRESHOLD_INDEX])
      ) {
        // daily activity is completed, add small loot box
        IUserController.EarnedLootBoxes memory earned = _S().counterLootBoxes[user];
        earned.dailyCounter += 1;
        userActivity.dailyLootBoxReceived = true;

        if (epochWeek == userActivity.epochWeek) {
          // continue current week
          userActivity.dailyActivities += 1;
          if (userActivity.dailyActivities == thresholds[WEEKLY_ACTIVITY_THRESHOLD_INDEX] && !userActivity.weeklyLootBoxReceived) {
            // weekly activity is completed, add large loot box
            userActivity.weeklyLootBoxReceived = true;
            earned.weeklyCounter += 1;
          }
        } else {
          // start new week
          userActivity.dailyActivities = 1;
          userActivity.epochWeek = epochWeek;
          userActivity.weeklyLootBoxReceived = false;
        }

        _S().counterLootBoxes[user] = earned;

        emit IApplicationEvents.ActivityCompleted(user, userActivity.dailyLootBoxReceived, userActivity.weeklyLootBoxReceived);
      }
    }

    _S().userActivity[user] = userActivity;
  }

  function registerFameHallHero(IController controller, address msgSender_, address hero, uint heroId, uint8 openedNgLevel) internal {
    _onlyHeroController(controller, msgSender_);

    if (_S().fameHall[openedNgLevel].heroOwner != address(0)) revert IAppErrors.FameHallHeroAlreadyRegistered(openedNgLevel);

    address heroOwner = IERC721(hero).ownerOf(heroId);
    _S().fameHall[openedNgLevel] = IUserController.FameHallData({
      hero: hero,
      heroId: uint64(heroId),
      heroOwner: heroOwner,
      tsOpen: uint64(block.timestamp)
    });

    emit IApplicationEvents.FameHallHeroRegistered(hero, heroId, heroOwner, openedNgLevel);
  }

  function useGamePointsToSkipStore(IController controller, address msgSender_, address user, uint16 storyId) internal {
    _onlyGOC(controller, msgSender_);

    if (!isStoryPassed(user, storyId)) revert IAppErrors.StoryNotPassed();
    uint priceInGamePoints = priceStorySkipping();

    uint balance = _S().gamePoints[user];
    // zero price is valid, assume that we always set not-zero default price in deploy scripts
    if (priceInGamePoints != 0) {
      if (balance < priceInGamePoints) revert IAppErrors.NotEnoughAmount(balance, priceInGamePoints);
      balance -= priceInGamePoints;
      _S().gamePoints[user] = balance;
    }

    emit IApplicationEvents.UseGamePointsToSkipStory(user, storyId, priceInGamePoints, balance);
  }

  function setStoryPassed(IController controller, address msgSender_, address user, uint16 storyId) internal {
    _onlyGOC(controller, msgSender_);

    EnumerableSet.Bytes32Set storage storyIds = _S().passedObjects[user];
    bytes32 hash = _getStoryIdHash(storyId);
    if (!storyIds.contains(hash)) {
      storyIds.add(hash);
      emit IApplicationEvents.SetStoryPassed(user, storyId);
    }
  }

  //endregion ------------------------ IUserController

  //region ------------------------ Utils
  /// @notice Calculate week for the given day. Assume that first day of the week is Monday
  function getEpochWeek(uint epochDay) internal pure returns (uint32) {
    return uint32((epochDay + 3) / 7); // + 3 to move start of the first week to Monday 1969-12-29
  }

  function _getStoryIdHash(uint16 storyId) internal pure returns (bytes32) {
    return bytes32(abi.encodePacked("STORY_", StringLib._toString(storyId)));
  }

  function _setParam(IController controller, address msgSender, IUserController.UserControllerParam paramId, uint paramValue) internal {
    _onlyDeployer(controller, msgSender);
    _S().userControllerParams[IUserController.UserControllerParam(paramId)] = paramValue;
    emit IApplicationEvents.SetUserControllerParam(uint8(paramId), paramValue);
  }
  //endregion ------------------------ Utils

}

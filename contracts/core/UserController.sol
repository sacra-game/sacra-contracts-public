// SPDX-License-Identifier: BUSL-1.1
/**
            ▒▓▒  ▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓███▓▓▒     ▒▒▒▒▓▓▓▒▓▓▓▓▓▓▓██▓
             ▒██▒▓▓▓▓█▓██████████████████▓  ▒▒▒▓███████████████▒
              ▒██▒▓█████████████████████▒ ▒▓██████████▓███████
               ▒███████████▓▒                   ▒███▓▓██████▓
                 █████████▒                     ▒▓▒▓███████▒
                  ███████▓      ▒▒▒▒▒▓▓█▓▒     ▓█▓████████
                   ▒▒▒▒▒   ▒▒▒▒▓▓▓█████▒      ▓█████████▓
                         ▒▓▓▓▒▓██████▓      ▒▓▓████████▒
                       ▒██▓▓▓███████▒      ▒▒▓███▓████
                        ▒███▓█████▒       ▒▒█████▓██▓
                          ██████▓   ▒▒▒▓██▓██▓█████▒
                           ▒▒▓▓▒   ▒██▓▒▓▓████████
                                  ▓█████▓███████▓
                                 ██▓▓██████████▒
                                ▒█████████████
                                 ███████████▓
      ▒▓▓▓▓▓▓▒▓                  ▒█████████▒                      ▒▓▓
    ▒▓█▒   ▒▒█▒▒                   ▓██████                       ▒▒▓▓▒
   ▒▒█▒       ▓▒                    ▒████                       ▒▓█▓█▓▒
   ▓▒██▓▒                             ██                       ▒▓█▓▓▓██▒
    ▓█▓▓▓▓▓█▓▓▓▒        ▒▒▒         ▒▒▒▓▓▓▓▒▓▒▒▓▒▓▓▓▓▓▓▓▓▒    ▒▓█▒ ▒▓▒▓█▓
     ▒▓█▓▓▓▓▓▓▓▓▓▓▒    ▒▒▒▓▒     ▒▒▒▓▓     ▓▓  ▓▓█▓   ▒▒▓▓   ▒▒█▒   ▒▓▒▓█▓
            ▒▒▓▓▓▒▓▒  ▒▓▓▓▒█▒   ▒▒▒█▒          ▒▒█▓▒▒▒▓▓▓▒   ▓██▓▓▓▓▓▓▓███▓
 ▒            ▒▓▓█▓  ▒▓▓▓▓█▓█▓  ▒█▓▓▒          ▓▓█▓▒▓█▓▒▒   ▓█▓        ▓███▓
▓▓▒         ▒▒▓▓█▓▒▒▓█▒   ▒▓██▓  ▓██▓▒     ▒█▓ ▓▓██   ▒▓▓▓▒▒▓█▓        ▒▓████▒
 ██▓▓▒▒▒▒▓▓███▓▒ ▒▓▓▓▓▒▒ ▒▓▓▓▓▓▓▓▒▒▒▓█▓▓▓▓█▓▓▒▒▓▓▓▓▓▒    ▒▓████▓▒     ▓▓███████▓▓▒
*/
pragma solidity 0.8.23;

import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IUserController.sol";
import "../lib/UserControllerLib.sol";
import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";

contract UserController is Initializable, Controllable, ERC2771Context, IUserController {
  //region ------------------------ CONSTANTS

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant override VERSION = "1.0.1";
  //endregion ------------------------ CONSTANTS

  //region ------------------------ INITIALIZER
  function init(address controller_) external initializer {
    __Controllable_init(controller_);

    UserControllerLib._S().feeRenaming = UserControllerLib.FEE_RENAMING_DEFAULT_VALUE;
  }
  //endregion ------------------------ INITIALIZER

  //region ------------------------ View
  function userAccountName(address userAccount) external view returns (string memory) {
    return UserControllerLib.getUserAccountName(userAccount);
  }

  function userAvatar(address userAccount) external view returns (string memory) {
    return UserControllerLib.getUserAvatar(userAccount);
  }

  function nameToUserAccount(string memory name) external view returns (address) {
    return UserControllerLib.nameToUserAccount(name);
  }

  function userActivity(address user) external view returns (IUserController.UserActivity memory) {
    return UserControllerLib.getUserActivity(user);
  }

  function counterLootBoxes(address user) external view returns (uint32 dailyCounter, uint32 weeklyCounter) {
    return UserControllerLib.getCounterLootBoxes(user);
  }

  function lootBoxConfig(uint lootBoxKind) external view returns (
    address[] memory mintItems,
    uint32[] memory mintItemsChances,
    uint maxDropItems
  ) {
    return UserControllerLib.getLootBoxConfig(lootBoxKind);
  }

  function feeRenaming() external view returns (uint) {
    return UserControllerLib.getFeeRenaming();
  }

  /// @return hero The hero who has opened given NG_LEVE first
  /// @return heroId ID of the hero who has opened given NG_LEVE first
  /// @return heroOwner The owner of the hero
  /// @return tsOpen Timestamp of the moment of opening of the given NG_LEVEL
  function fameHallHero(uint8 openedNgLevel) external view returns (address hero, uint heroId, address heroOwner, uint64 tsOpen) {
    return UserControllerLib.fameHallHero(openedNgLevel);
  }

  function gamePoints(address user) external view returns (uint countGamePoints) {
    return UserControllerLib.gamePoints(user);
  }

  function isStoryPassed(address user, uint16 storyId) external view returns (bool) {
    return UserControllerLib.isStoryPassed(user, storyId);
  }

  function priceStorySkipping() external view returns (uint) {
    return UserControllerLib.priceStorySkipping();
  }
  //endregion ------------------------ View

  //region ------------------------ ACTIONS
  function setUserName(string memory name) external {
    UserControllerLib.setUserName(_isNotSmartContract(), IController(controller()), _msgSender(), name);
  }

  function setUserAvatar(string memory avatar) external {
    UserControllerLib.setUserAvatar(_isNotSmartContract(), IController(controller()), _msgSender(), avatar);
  }

  function openLootBox(uint lootBoxKind) external {
    UserControllerLib.openLootBox(
      IController(controller()),
      _msgSender(),
      IUserController.LootBoxKind(lootBoxKind),
      CalcLib.nextPrng,
      ItemLib._mintRandomItems
    );
  }
  //endregion ------------------------ ACTIONS

  //region ------------------------ Deployer actions
  function setLootBoxConfig(uint lootBoxKind, IUserController.LootBoxConfig memory config) external {
    UserControllerLib.setLootBoxConfig(IController(controller()), _msgSender(), lootBoxKind, config);
  }

  function setFeeRenaming(uint amount) external {
    UserControllerLib.setFeeRenaming(IController(controller()), _msgSender(), amount);
  }

  function setPriceStorySkipping(uint priceInGamePoints) external {
    return UserControllerLib.setPriceStorySkipping(IController(controller()), _msgSender(), priceInGamePoints);
  }
  //endregion ------------------------ Deployer actions

  //region ------------------------ IUserController
  function registerPassedDungeon(address user) external {
    UserControllerLib.registerPassedDungeon(
      IController(controller()),
      _msgSender(),
      user,
      block.timestamp,
      [UserControllerLib.DAILY_ACTIVITY_DUNGEONS_THRESHOLD,
      UserControllerLib.WEEKLY_ACTIVITY_THRESHOLD,
      UserControllerLib.DAILY_ACTIVITY_PVP_THRESHOLD]
    );
  }

  function registerPvP(address user, bool isWinner) external {
    UserControllerLib.registerPvP(
      IController(controller()),
      _msgSender(),
      user,
      block.timestamp,
      [UserControllerLib.DAILY_ACTIVITY_DUNGEONS_THRESHOLD,
      UserControllerLib.WEEKLY_ACTIVITY_THRESHOLD,
      UserControllerLib.DAILY_ACTIVITY_PVP_THRESHOLD],
      isWinner
    );
  }

  /// @notice Register the hero who has opened given NG_LEVE first in the Hall of Fame
  function registerFameHallHero(address hero, uint heroId, uint8 openedNgLevel) external {
    UserControllerLib.registerFameHallHero(IController(controller()), _msgSender(), hero, heroId, openedNgLevel);
  }

  /// @notice Check if user has enough game points to skip the story and the story was passed by the user.
  /// Reduce number of user's game points on the cost of story skipping.
  function useGamePointsToSkipStore(address user, uint16 storyId) external {
    UserControllerLib.useGamePointsToSkipStore(IController(controller()), _msgSender(), user, storyId);
  }

  function setStoryPassed(address user, uint16 storyId) external {
    UserControllerLib.setStoryPassed(IController(controller()), _msgSender(), user, storyId);
  }
  //endregion ------------------------ IUserController
}

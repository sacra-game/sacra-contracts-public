// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "../openzeppelin/EnumerableSet.sol";

interface IUserController {

  //region ------------------------ Data types

  enum LootBoxKind {
    /// @notice small loot box - reward for the daily activity
    DAILY_0,
    /// @notice large loot box - reward for the weekly activity (daily activity is passed each ot of the 7 days)
    WEEKLY_1,

    END_SLOT
  }

  /// @dev registerPassedDungeon assumes that the whole struct takes single slot only, not more
  struct UserActivity {
    /// @notice A day for which the daily activity is calculated (see counterXXX below)
    /// The number of days since 1970-01-01
    uint32 epochDay;

    /// @notice A week for which total count of daily activities were calculated
    /// The number of weeks since (1970-01-01 Thursday) - 3 days = (1969-12-29 Monday)
    uint32 epochWeek;

    /// @notice Count of dungeons passed during the day
    uint32 counterPassedDungeons;
    /// @notice Count of PvP during the day
    uint32 counterPvp;

    /// @notice Count of daily activities completed per the week
    uint16 dailyActivities;

    /// @notice Daily activity is completed and small loot box is added to the earned loot boxes
    bool dailyLootBoxReceived;
    /// @notice Weekly activity is completed and large loot box is added to the earned loot boxes
    bool weeklyLootBoxReceived;
  }

  struct EarnedLootBoxes {
    /// @notice Count of loot boxes earned by daily activity
    uint32 dailyCounter;
    /// @notice Count of loot boxes earned by weekly activity
    uint32 weeklyCounter;
  }

  struct LootBoxConfig {
    address[] mintItems;
    uint32[] mintItemsChances;
    uint maxDropItems;
  }

  enum UserControllerParam {
    /// @notice Price of story skipping in game points
    PRICE_STORY_SKIPPING_1
  }

  /// @custom:storage-location erc7201:user.controller.main
  struct MainState {
    /// @notice Amount of sacra required to rename user account
    uint feeRenaming;

    /// @dev user EOA => account name
    mapping(address => string) userAccountName;

    /// @dev name => user EOA, needs for checking uniq names
    mapping(string => address) nameToUserAccount;

    /// @notice user => daily activity info
    mapping(address => UserActivity) userActivity;

    /// @notice user => earned loot boxes
    mapping(address => EarnedLootBoxes) counterLootBoxes;

    /// @notice Configs of loot boxes of various kinds
    mapping(LootBoxKind => LootBoxConfig) lootBoxConfig;

    /// @dev Deprecated, controller is used instead.
    address userTokensVault;

    /// @dev user EOA => account avatar
    mapping(address => string) userAvatar;

    // @notice Hall of Fame: ngLevel [1...99] => who opened the NG_LEVEL first
    mapping(uint8 ngLevel => FameHallData) fameHall;

    /// @notice Points earned for passing dungeons
    mapping(address user => uint gamePoints) gamePoints;

    /// @notice List of objects (currently only stories) passed by the given account
    /// @dev hashes of the stories are as encodePacked("STORY_{ID}")
    mapping(address user => EnumerableSet.Bytes32Set hashes) passedObjects;

    /// @notice Values of various params, see {UserControllerParam}
    mapping(UserControllerParam paramId => uint value) userControllerParams;
  }

  struct FameHallData {
    // ------------ slot 1
    /// @notice The hero who opened given the NG_LEVEL first
    address hero;
    uint64 heroId;
    // ------------ slot 2
    /// @notice The owner of the hero
    address heroOwner;
    /// @notice Timestamp of the moment of the opening given NG_LEVEL
    uint64 tsOpen;
  }

  //endregion ------------------------ Data types

  /// @notice Register daily activity - a dungeon was passed
  /// @param user Owner of the hero who has passed the dungeon
  function registerPassedDungeon(address user) external;

  /// @notice Register daily activity - PvP was made
  /// @param user Owner of the hero who has taken participation in the PvP
  function registerPvP(address user, bool isWinner) external;

  function registerFameHallHero(address hero, uint heroId, uint8 openedNgLevel) external;

  function useGamePointsToSkipStore(address user, uint16 storyId) external;

  function setStoryPassed(address user, uint16 storyId) external;

  function isStoryPassed(address user, uint16 storyId) external view returns (bool);
}

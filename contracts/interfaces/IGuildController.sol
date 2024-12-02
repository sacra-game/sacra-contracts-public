// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../openzeppelin/EnumerableSet.sol";

interface IGuildController {
  enum GuildRightBits {
    ADMIN_0,
    RENAME_1,
    CHANGE_LOGO_2,
    CHANGE_SHELTER_3,
    ADD_MEMBER_4,
    REMOVE_MEMBER_5,
    BANK_TOKENS_OPERATION_6,
    CHANGE_ROLES_7,
    LEVEL_UP_8,
    SET_RELATION_KIND_9,
    BANK_ITEMS_OPERATION_10,
    SET_GUILD_PARAMS_11,
    CHANGE_PURCHASING_SHELTER_ITEMS_CAPACITY_12
  }

  enum GuildsParams {
    NONE_0,
    COUNTER_GUILD_IDS_1,
    BASE_FEE_2,
    COUNTER_GUILD_REQUESTS_3,
    REENTRANT_STATUS_4,
    SHELTER_CONTROLLER_5,
    SHELTER_AUCTION_6
  }

  enum GuildRequestStatus {
    NONE_0,
    ACCEPTED_1,
    REJECTED_2,
    CANCELED_3
  }

  /// @custom:storage-location erc7201:guild.controller.main
  struct MainState {
    /// @notice Mapping to store various guilds params (with global values for all guilds)
    mapping(GuildsParams param => uint value) guildsParam;

    /// @notice guildId => address of instance of GuildBank contract
    mapping(uint guildId => address) guildBanks;

    /// @notice guild id => guild data (owner, name, logo, etc)
    mapping(uint guildId => GuildData) guildData;

    /// @notice name => guild id
    mapping(string guildName => uint guildId) nameToGuild;

    /// @notice EOA => guild id, EOA can be a member of a single guild only
    mapping(address member => uint guildId) memberToGuild;

    /// @notice List of participants of guilds
    /// @dev Allowed number of members is 20 + 5 * guildLevel
    mapping(uint guildId => EnumerableSet.AddressSet listEoa) members;

    /// @notice Rights of the member in the guild, mask of GuildRightBits
    mapping(address member => uint maskRights) rights;

    /// @notice _getGuildsPairKey(guild1, guild2) => status (false - war, true - peace)
    mapping(bytes32 guildsPairKey => bool) relationsPeaceful;

    // ---------------------------- Request to join to the guild
    /// @notice Full list of requests registered for the guild
    mapping(uint guildId => mapping(GuildRequestStatus status => EnumerableSet.UintSet guildRequestIds)) guildRequests;

    /// @notice List of active requests created by the given user.
    /// "Active" => deposit should be returned to the user.
    /// All not-active requests are removed from here automatically.
    mapping(address user => EnumerableSet.UintSet guildRequestIds) userActiveGuildRequests;

    /// @notice Data of all guild requests ever created
    mapping(uint guildRequestId => GuildRequestData) guildRequestData;

    /// @notice Deposit amount required to create a guild request
    mapping(uint guildId => GuildRequestDeposit) guildRequestDepositAmounts;

    /// @notice Counter of spent pvp points + number of guild pvp-points allowed to be used by the guild member
    mapping(uint guildId => mapping(address member => UserPvpPoints)) userPvpPoints;

    /// @notice guild id => guildDescription
    mapping(uint guildId => string) guildDescription;
  }

  struct GuildData {
    /// @notice Not empty unique guild name
    string guildName;

    /// @notice URL of guild logo (empty is allowed)
    string urlLogo;

    /// @notice Creator (owner) of the guild
    address owner;

    /// @notice Guild level [1...10]
    uint8 guildLevel;

    /// @notice Percent of guild reinforcement fee Value in range [_FEE_MIN ... _TO_HELPER_RATIO_MAX], i.e. [10..50]
    uint8 toHelperRatio;

    /// @notice Global guild points counter, it's incremented on each victory in php-fight.
    /// @dev Assume here, that uint64 is enough to store any sums of scores
    uint64 pvpCounter;
  }

  struct GuildRequestData {
    GuildRequestStatus status;
    /// @notice Creator of the guild request that asks to include him to the guild
    address user;
    /// @notice Message to the guild owner from the user
    string userMessage;
    uint guildId;
  }

  struct GuildRequestDeposit {
    bool initialized;
    uint192 amount;
  }

  struct UserPvpPoints {
    /// @notice How many guild pvp-points the user is allowed to use
    uint64 capacityPvpPoints;

    /// @notice How many guild pvp-points the user has used
    uint64 spentPvpPoints;
  }

  /// ----------------------------------------------------------------------------------------------

  function memberOf(address user) external view returns (uint guildId);
  function guildToShelter(uint guildId) external view returns (uint shelterId);

  function getGuildData(uint guildId) external view returns (
    string memory guildName,
    string memory urlLogo,
    address owner,
    uint8 guildLevel,
    uint64 pvpCounter,
    uint toHelperRatio
  );

  function getRights(address user) external view returns (uint);
  function getGuildBank(uint guildId) external view returns (address);
  function shelterController() external view returns (address);

  function usePvpPoints(uint guildId, address user, uint64 priceInPvpPoints) external;
  function payFromGuildBank(uint guildId, uint shelterPrice) external;
  function payFromBalance(uint amount, address user) external;

  /// @notice Ensure that the {user} has given {right}, revert otherwise
  function checkPermissions(address user, uint right) external view returns (uint guildId, uint rights);
  function shelterAuctionController() external view returns (address);
  function payForAuctionBid(uint guildId, uint amount, uint bid) external;
}

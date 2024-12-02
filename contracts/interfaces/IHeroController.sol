// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;
import "../openzeppelin/EnumerableSet.sol";
import "../openzeppelin/EnumerableMap.sol";

interface IHeroController {

  /// @custom:storage-location erc7201:hero.controller.main
  struct MainState {

    /// @dev A central place for all hero tokens
    /// @dev Deprecated. Controller is used instead.
    address heroTokensVault;

    /// @dev heroAdr => packed tokenAdr160+ amount96
    mapping(address => bytes32) payToken;

    /// @dev heroAdr => heroCls8
    mapping(address => uint8) heroClass;

    // ---

    /// @dev hero+id => individual hero name
    mapping(bytes32 => string) heroName;

    /// @dev name => hero+id, needs for checking uniq names
    mapping(string => bytes32) nameToHero;

    // ---

    /// @dev hero+id => biome
    mapping(bytes32 => uint8) heroBiome;

    /// @notice Exist reinforcement of any kind for the given hero
    /// @dev hero+id => packed reinforcement helper+id
    mapping(bytes32 => bytes32) reinforcementHero;

    /// @dev hero+id => reinforcement packed attributes
    mapping(bytes32 => bytes32[]) reinforcementHeroAttributes;

    /// @notice packedHero (hero + id) => count of calls of beforeTokenTransfer
    mapping(bytes32 => uint) countHeroTransfers;


    // ------------------------------------ NG plus

    /// @notice (tier, hero address) => TierInfo, where tier = [2, 3]
    /// @dev For tier=1 no data is required. Amount for tier 1 is stored in {payToken}, no items are minted
    /// Token from {payToken} is equal for all tiers
    mapping(bytes32 packedTierHero => TierInfo) tiers;

    mapping(bytes32 packedHero => HeroInfo) heroInfo;

    /// @notice Max NG_LVL reached by the heroes of a given account
    mapping(address user => uint8 maxNgLevel) maxUserNgLevel;

    /// @notice When the hero has killed boss on the given biome first time
    /// packedBiomeNgLevel = packed (biome, NG_LEVEL)
    mapping(bytes32 packedHero => mapping (bytes32 packedBiomeNgLevel => uint timestamp)) killedBosses;

    /// @notice Max NG_LEVEL reached by any user
    uint maxOpenedNgLevel;
  }

  /// @notice Tier = hero creation cost option
  /// There are 3 tiers:
  /// 1: most chip option, just pay fixed amount {payTokens} - new hero is created
  /// 2: pay bigger amount - random skill is equipped on the newly created hero
  /// 3: pay even more amount - random sill + some random items are equipped on the newly created hero
  struct TierInfo {
    /// @notice Cost of the hero creation using the given tier in terms of the token stored in {payToken}
    /// This amount is used for tiers 2, 3. For tier 1 the amount is taken from {payToken}
    uint amount;

    /// @notice All slots for which items-to-mint are registered in {itemsToMint}
    EnumerableSet.UintSet slots;

    /// @notice slot => items that can be minted and equipped on the hero to the given {slot} after hero creation
    mapping(uint8 slot => address[] items) itemsToMint;
  }

  /// @notice Current NG+-related values
  struct HeroInfo {
    /// @notice Hero tier = [0..3]. 0 - the hero is post-paid, it can be changed by upgrading the hero to pre-paid
    uint8 tier;

    /// @notice NG_LVL of the hero
    uint8 ngLevel;

    /// @notice True if hero has passed last biome on current NG+ and so NG_LEVEL can be incremented (reborn is allowed)
    bool rebornAllowed;

    /// @notice Amount paid for the hero on creation OR on upgrade to NG+
    /// Amount paid for creation of the hero in terms of game token (!NG+) is NOT stored here.
    /// @dev uint72 is used here to pack the whole struct to single slot
    uint72 paidAmount;

    /// @notice Pay token used to pay {paidAmount}
    address paidToken;
  }

  /// @notice Input data to create new hero
  struct HeroCreationData {
    /// @notice Desired NG_LVL of the hero
    uint8 ngLevel;

    /// @notice Desired tire of the newly created hero. Allowed values: [1..3]
    uint8 tier;

    /// @notice Enter to the dungeon after creation
    bool enter;

    /// @notice Desired hero name
    string heroName;

    /// @notice Optional: user account for which the hero is created
    address targetUserAccount;

    /// @notice Optional: ref-code to be passed to the hero-creation-related event
    string refCode;
  }


  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  function heroClass(address hero) external view returns (uint8);

  function heroBiome(address hero, uint heroId) external view returns (uint8);

  function payTokenInfo(address hero) external view returns (address token, uint amount);

  function heroReinforcementHelp(address hero, uint heroId) external view returns (address helperHeroToken, uint helperHeroId);

  function score(address hero, uint heroId) external view returns (uint);

  function isAllowedToTransfer(address hero, uint heroId) external view returns (bool);

  function beforeTokenTransfer(address hero, uint heroId) external returns (bool);

  // ---

  function create(address hero, string memory heroName_, bool enter) external returns (uint);

  function kill(address hero, uint heroId) external returns (bytes32[] memory dropItems);

  /// @notice Take off all items from the hero, reduce life to 1. The hero is NOT burnt.
  /// Optionally reduce mana to zero and/or decrease life chance.
  function softKill(address hero, uint heroId, bool decLifeChances, bool resetMana) external returns (bytes32[] memory dropItems);

  function releaseReinforcement(address hero, uint heroId) external returns (address helperToken, uint helperId);

  function resetLifeAndMana(address hero, uint heroId) external;

  function countHeroTransfers(address hero, uint heroId) external view returns (uint);

  function askGuildReinforcement(address hero, uint heroId, address helper, uint helperId) external;

  function getHeroInfo(address hero, uint heroId) external view returns (IHeroController.HeroInfo memory data);

  function registerKilledBoss(address hero, uint heroId, uint32 objectId) external;

  function maxOpenedNgLevel() external view returns (uint);
}

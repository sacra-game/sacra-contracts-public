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

import "../proxy/Controllable.sol";
import "../lib/DungeonFactoryLib.sol";
import "../relay/ERC2771Context.sol";
import "../openzeppelin/ERC721Holder.sol";

contract DungeonFactory is Controllable, IDungeonFactory, ERC2771Context, ERC721Holder {
  //region ------------------------ CONSTANTS

  /// @notice Version of the contract
  string public constant override VERSION = "2.1.1";
  //endregion ------------------------ CONSTANTS

  //region ------------------------ INITIALIZER
  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ INITIALIZER

  //region ------------------------ VIEWS
  function dungeonAttributes(uint16 dungLogicNum) external view returns (DungeonAttributes memory) {
    return DungeonFactoryLib.dungeonAttributes(dungLogicNum);
  }

  function dungeonStatus(uint64 dungeonId) external view returns (
    uint16 dungNum,
    bool isCompleted,
    address heroToken,
    uint heroTokenId,
    uint32 currentObject,
    uint8 currentObjIndex,
    address[] memory treasuryTokens,
    uint[] memory treasuryTokensAmounts,
    bytes32[] memory treasuryItems,
    uint8 stages,
    uint32[] memory uniqObjects
  ) {
    return DungeonFactoryLib.dungeonStatus(dungeonId);
  }

  function dungeonCounter() external view returns (uint64) {
    return DungeonFactoryLib.dungeonCounter();
  }

  function maxBiomeCompleted(address heroToken, uint heroTokenId) external view override returns (uint8) {
    return DungeonFactoryLib.maxBiomeCompleted(heroToken, heroTokenId);
  }

  function currentDungeon(address heroToken, uint heroTokenId) external view override returns (uint64) {
    return DungeonFactoryLib.currentDungeon(heroToken, heroTokenId);
  }

  function minLevelForTreasury(address token) external view returns (uint) {
    return DungeonFactoryLib.minLevelForTreasury(token);
  }

  function skillSlotsForDurabilityReduction(address heroToken, uint heroTokenId) external override view returns (uint8[] memory result) {
    return DungeonFactoryLib.skillSlotsForDurabilityReduction(heroToken, heroTokenId);
  }

  function freeDungeonsByLevelLength(uint biome) external view returns (uint) {
    return DungeonFactoryLib.freeDungeonsByLevelLength(biome);
  }

  function freeDungeonsByLevel(uint id, uint biome) external view returns (uint64) {
    return DungeonFactoryLib.freeDungeonsByLevel(id, biome);
  }

  function dungeonTreasuryReward(
    address token,
    uint maxAvailableBiome_,
    uint treasuryBalance,
    uint8 heroLevel,
    uint8 dungeonBiome,
    uint8 maxOpenedNgLevel,
    uint8 heroNgLevel
  ) external view returns (uint) {
    return DungeonLib.dungeonTreasuryReward(token, maxAvailableBiome_, treasuryBalance, heroLevel, dungeonBiome, maxOpenedNgLevel, heroNgLevel);
  }

  function getDungeonTreasuryAmount(address token, uint heroLevel, uint biome, uint heroNgLevel) external view returns (
    uint totalAmount,
    uint amountForDungeon,
    uint mintAmount
  ) {
    return DungeonFactoryLib.getDungeonTreasuryAmount(IController(controller()), token, heroLevel, biome, heroNgLevel);
  }

  function getDungeonLogic(IController controller_, uint8 heroLevel, address heroToken, uint heroTokenId, uint random)
  external view returns (uint16) {
    ControllerContextLib.ControllerContext memory cc = ControllerContextLib.init(controller_);
    return DungeonLib.getDungeonLogic(DungeonLib._S(), cc, heroLevel, heroToken, heroTokenId, random);
  }

  function isDungeonEligibleForHero(uint16 dungeonLogic, uint8 heroLevel, address heroToken, uint heroTokenId)
  external view returns (bool) {
    return DungeonLib.isDungeonEligibleForHero(
      DungeonLib._S(),
      IStatController(IController(controller()).statController()),
      dungeonLogic,
      heroLevel,
      heroToken,
      heroTokenId
    );
  }

  /// @dev Easily get info should given hero fight with boss in the current biome or not.
  function isBiomeBoss(address heroToken, uint heroTokenId) external view returns (bool) {
    return DungeonFactoryLib.isBiomeBoss(IController(controller()), heroToken, heroTokenId);
  }

  function maxAvailableBiome() external view returns (uint8) {
    return DungeonFactoryLib.maxAvailableBiome();
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ ACTIONS

  function launch(address heroToken, uint heroTokenId, address treasuryToken) external returns (uint64 dungeonId) {
    return DungeonFactoryLib.launch(_isNotSmartContract(), IController(controller()), _msgSender(), heroToken, heroTokenId, treasuryToken);
  }

  function launchForNewHero(address heroToken, uint heroTokenId, address owner) external override returns (uint64 dungeonId) {
    return DungeonFactoryLib.launchForNewHero(IController(controller()), owner, heroToken, heroTokenId);
  }

  function setBossCompleted(uint32 objectId, address heroToken, uint heroTokenId, uint8 heroBiome) external override {
    DungeonFactoryLib.setBossCompleted(IController(controller()), objectId, heroToken, heroTokenId, heroBiome);
  }
  //endregion ------------------------ ACTIONS

  //////////////////////////////////////////////////////////////////////////////////////
  //           DUNGEON LOGIC
  //////////////////////////////////////////////////////////////////////////////////////

  //region ------------------------ GOV ACTIONS

  /// @notice Register ordinal or specific dungeon
  /// @param biome Assume biome > 0
  /// @param isSpecific The dungeon is specific, so it shouldn't be registered in dungeonsLogicByBiome
  /// @param specReqBiome required biome
  /// @param specReqHeroClass required hero class
  function registerDungeonLogic(
    uint16 dungLogicId,
    uint8 biome,
    DungeonGenerateInfo memory genInfo,
    uint8 specReqBiome,
    uint8 specReqHeroClass,
    bool isSpecific
  ) external {
    DungeonFactoryLib.registerDungeonLogic(
      IController(controller()),
      dungLogicId,
      biome,
      genInfo,
      specReqBiome,
      specReqHeroClass,
      isSpecific
    );
  }

  function removeDungeonLogic(uint16 dungLogicId, uint8 specReqBiome, uint8 specReqHeroClass) external {
    DungeonFactoryLib.removeDungeonLogic(IController(controller()), dungLogicId, specReqBiome, specReqHeroClass);
  }

  /// @dev Set eligible hero level for treasury tokens
  function setMinLevelForTreasury(address token, uint heroLevel) external {
    DungeonFactoryLib.setMinLevelForTreasury(IController(controller()), token, heroLevel);
  }

  /// @dev Governance can drop hero from dungeon in emergency case
  function emergencyExit(uint64 dungId) external {
    DungeonFactoryLib.emergencyExit(IController(controller()), dungId);
  }
  //endregion ------------------------ GOV ACTIONS

  //region ------------------------ USER ACTIONS
  function enter(uint64 dungId, address heroToken_, uint heroTokenId_) external {
    DungeonFactoryLib.enter(_isNotSmartContract(), IController(controller()), _msgSender(), dungId, heroToken_, heroTokenId_);
  }

  function openObject(uint64 dungId) external {
    DungeonFactoryLib.openObject(_isNotSmartContract(), IController(controller()), _msgSender(), dungId);
  }

  function objectAction(uint64 dungId, bytes memory data) external {
    DungeonFactoryLib.objectAction(_isNotSmartContract(), IController(controller()), _msgSender(), dungId, data);
  }

  function exit(uint64 dungId, bool claim) external {
    DungeonFactoryLib.exit(_isNotSmartContract(), IController(controller()), _msgSender(), dungId, claim);
  }
  //endregion ------------------------ USER ACTIONS

  //region ------------------------ Contracts actions

  /// @notice Hero exists current dungeon forcibly same as when dying but without loosing life chance
  /// @dev Implement logic of special consumable that allows a hero to exit current dungeon using the shelter
  function exitForcibly(address heroToken, uint heroTokenId, address msgSender) override external {
    DungeonFactoryLib.exitForcibly(IController(controller()), heroToken, heroTokenId, msgSender);
  }

  function reborn(address heroToken, uint heroTokenId) external override {
    DungeonFactoryLib.reborn(IController(controller()), heroToken, heroTokenId);
  }
  //endregion ------------------------ Contracts actions
}

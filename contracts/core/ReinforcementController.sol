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
import "../relay/ERC2771Context.sol";
import "../interfaces/IReinforcementController.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IDungeonFactory.sol";
import "../openzeppelin/ERC721Holder.sol";
import "../lib/PackingLib.sol";
import "../lib/ReinforcementControllerLib.sol";

contract ReinforcementController is Controllable, IReinforcementController, ERC721Holder, ERC2771Context {
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using PackingLib for bytes32;
  using PackingLib for address;
  using PackingLib for uint8[];

  //region ------------------------ CONSTANTS

  /// @notice Version of the contract
  string public constant override VERSION = "2.0.1";
  //endregion ------------------------ CONSTANTS

  //region ------------------------ INITIALIZER

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ INITIALIZER

  //region ------------------------ VIEWS
  function minLevel() external view returns (uint8 _minLevel) {
    return ReinforcementControllerLib.minLevel();
  }

  function minLifeChances() external view returns (uint8 _minLifeChances) {
    return ReinforcementControllerLib.minLifeChances();
  }

  function toHelperRatio(address heroToken, uint heroId) external override view returns (uint) {
    return ReinforcementControllerLib.toHelperRatio(heroToken, heroId);
  }

  function heroInfo(address heroToken, uint heroId) external view returns (HeroInfo memory) {
    return ReinforcementControllerLib.heroInfo(heroToken, heroId);
  }

  function isStaked(address heroToken, uint heroId) external view override returns (bool) {
    return ReinforcementControllerLib.isStaked(heroToken, heroId);
  }

  function maxScore(uint biome) external view returns (uint) {
    return ReinforcementControllerLib.maxScore(biome);
  }

  function earned(address heroToken, uint heroId) external view returns (
    address[] memory tokens,
    uint[] memory amounts,
    address[] memory nfts,
    uint[] memory ids
  ) {
    return ReinforcementControllerLib.earned(heroToken, heroId);
  }

  function heroScoreAdjusted(address heroToken, uint heroId) external view returns (uint) {
    return ReinforcementControllerLib.heroScoreAdjusted(heroToken, heroId);
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ GOV ACTIONS

  function setMinLevel(uint8 value) external {
    ReinforcementControllerLib.setMinLevel(isGovernance(msg.sender), value);
  }

  function setMinLifeChances(uint8 value) external {
    ReinforcementControllerLib.setMinLifeChances(isGovernance(msg.sender), value);
  }

  //endregion ------------------------ GOV ACTIONS

  //region ------------------------ USER ACTIONS

  function stakeHero(address heroToken, uint heroId, uint8 fee) external {
    ReinforcementControllerLib.stakeHero(_isNotSmartContract(), IController(controller()), _msgSender(), heroToken, heroId, fee);
  }

  function withdrawHero(address heroToken, uint heroId) external {
    ReinforcementControllerLib.withdrawHero(_isNotSmartContract(), IController(controller()), _msgSender(), heroToken, heroId);
  }

  /// @dev It's view like function but we need to touch slots in oracle function.
  function askHero(uint biome) external override returns (address heroToken, uint heroId, int32[] memory attributes) {
    return ReinforcementControllerLib.askHero(IController(controller()), biome);
  }

  /// @dev Only for dungeon. Assume the tokens already sent to this contract.
  function registerTokenReward(address heroToken, uint heroId, address token, uint amount) external override {
    ReinforcementControllerLib.registerTokenReward(IController(controller()), heroToken, heroId, token, amount);
  }

  /// @dev Only for dungeon. Assume the NFT already sent to this contract.
  function registerNftReward(address heroToken, uint heroId, address token, uint tokenId) external override {
    ReinforcementControllerLib.registerNftReward(IController(controller()), heroToken, heroId, token, tokenId);
  }

  function claimAll(address heroToken, uint heroId) external {
    ReinforcementControllerLib.claimAll(_isNotSmartContract(), IController(controller()), _msgSender(), heroToken, heroId);
  }
  //endregion ------------------------ USER ACTIONS
}

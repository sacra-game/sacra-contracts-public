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

import "../interfaces/IGameToken.sol";
import "../interfaces/IMinter.sol";
import "../interfaces/IController.sol";
import "../lib/CalcLib.sol";
import "../lib/StatLib.sol";
import "../openzeppelin/Math.sol";

contract Minter is IMinter {
  using CalcLib for uint;

  //region ------------------------ Constants

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant VERSION = "1.0.1";

  uint private constant _MIN_BASE = 1;
  uint private constant _TOTAL_SUPPLY_BASE = 10_000_000e18;
  //endregion ------------------------ Constants

  //region ------------------------ Variables

  IController public immutable controller;
  IGameToken public immutable token;
  mapping(uint64 => bool) public dungeonMinted;
  bool public finalized;
  //endregion ------------------------ Variables

  //region ------------------------ Constructors

  constructor(address token_, address controller_) {
    token = IGameToken(token_);
    controller = IController(controller_);
  }
  //endregion ------------------------ Constructors

  //region ------------------------ Restrictions

  function onlyDungeonFactory() internal view {
    require(controller.dungeonFactory() == msg.sender, "Not dungeon factory");
  }

  function onlyGovernance() internal view {
    require(controller.governance() == msg.sender, "Not gov");
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Main logic

  function amountForDungeon(uint dungeonBiomeLevel, uint heroLvl) public view override returns (uint) {
    require(dungeonBiomeLevel < 20, "Too high biome");
    uint totalSupply = Math.max(token.totalSupply(), 1);
    uint base = Math.min(Math.max(_TOTAL_SUPPLY_BASE * 1e18 / totalSupply, _MIN_BASE), 20e18);
    base = base * (dungeonBiomeLevel ** 3) * 4;

    if(dungeonBiomeLevel == 1) {
      base = base / 10;
    }

    uint heroBiome = heroLvl / StatLib.BIOME_LEVEL_STEP + 1;
    // reduce amount if hero not in his biome
    if (heroBiome > dungeonBiomeLevel) {
      base = base / (2 ** (heroBiome - dungeonBiomeLevel));
    }
    return base;
  }

  function mintDungeonReward(uint64 dungeonId, uint dungeonBiomeLevel, uint heroLvl) external override returns (uint amount) {
    onlyDungeonFactory();
    require(!dungeonMinted[dungeonId], "Already minted");

    amount = amountForDungeon(dungeonBiomeLevel, heroLvl);
    if (amount != 0) {
      token.mint(msg.sender, amount);
    }
    dungeonMinted[dungeonId] = true;
  }
  //region ------------------------ Main logic

  //region ------------------------ Gov actions

  function transferMinter(address value) external {
    onlyGovernance();
    require(!finalized, "finalized");
    token.setMinter(value);
  }

  function pause(bool value) external {
    onlyGovernance();
    token.pause(value);
  }

  /// @dev Stop possibility change minter
  function finalize() external {
    onlyGovernance();
    finalized = true;
  }
  //endregion ------------------------ Gov actions
}

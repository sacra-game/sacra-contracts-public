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
import "../interfaces/IOracle.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IAppErrors.sol";

contract Oracle is Controllable, IOracle {

  //region ------------------------ Constants

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant override VERSION = "1.0.1";
  //endregion ------------------------ Constants

  // ---- VARIABLES ----

  //region ------------------------ Initializer

  function init(
    address controller_
  ) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ Initializer

  // ---- RESTRICTIONS ----

  //region ------------------------ Actions

  function getRandomNumber(uint max, uint seed) external override returns (uint) {
    return _getRandomNumber(max, seed);
  }

  function _getRandomNumber(uint maxValue, uint seed) internal returns (uint) {
    if (maxValue == 0) revert IAppErrors.OracleWrongInput();

    uint salt;

// Following code is commented because currently SkaleNetworks is not used
//    // skale has a RNG Endpoint
//    if (isSkaleNetwork()) {
//      assembly {
//        let freemem := mload(0x40)
//        let start_addr := add(freemem, 0)
//        if iszero(staticcall(gas(), 0x18, 0, 0, start_addr, 32)) {
//          invalid()
//        }
//        salt := mload(freemem)
//      }
//    }

    // pseudo random number
    bytes32 hash = keccak256(abi.encodePacked(blockhash(block.number), block.coinbase, block.difficulty, block.number, block.timestamp, msg.sender, tx.gasprice, gasleft(), uint(salt), seed));
    uint r = (uint(hash) % (maxValue + 1));
    emit IApplicationEvents.Random(r, maxValue);
    return r;
  }

  function getRandomNumberInRange(uint min, uint max, uint seed) external override returns (uint) {
    if (min >= max) {
      return max;
    }
    uint r = _getRandomNumber(max - min, seed);
    return min + r;
  }

// Following code is commented because currently SkaleNetworks is not used
//  function isSkaleNetwork() public view returns (bool) {
//    return block.chainid == uint(1351057110);
//  }
  //endregion ------------------------ Actions

}

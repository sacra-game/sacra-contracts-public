// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../solady/LibPRNG.sol";

library CalcLib {

  uint32 public constant MAX_CHANCE = 1e9;

  function minI32(int32 a, int32 b) internal pure returns (int32) {
    return a < b ? a : b;
  }

  function max32(int32 a, int32 b) internal pure returns (int32) {
    return a >= b ? a : b;
  }

  function absDiff(int32 a, int32 b) internal pure returns (uint32) {
    if (!((a >= 0 && b >= 0) || (a <= 0 && b <= 0))) revert IAppErrors.AbsDiff(a, b);
    if (a < 0) {
      a = - a;
    }
    if (b < 0) {
      b = - b;
    }
    return uint32(uint(int(a >= b ? a - b : b - a)));
  }

  function toUint(int32 n) internal pure returns (uint) {
    if (n <= 0) {
      return 0;
    }
    return uint(int(n));
  }

  function toInt32(uint a) internal pure returns (int32){
    if (a >= uint(int(type(int32).max))) {
      return type(int32).max;
    }
    return int32(int(a));
  }

  /// @dev Simplified pseudo-random for minor functionality
  function pseudoRandom(uint maxValue) internal view returns (uint) {
    if (maxValue == 0) {
      return 0;
    }

    uint salt = genSalt();
    // pseudo random number
    return (uint(keccak256(abi.encodePacked(blockhash(block.number), block.coinbase, block.difficulty, block.number, block.timestamp, tx.gasprice, gasleft(), salt))) % (maxValue + 1));
  }

  function genSalt() internal view returns (uint salt) {
    // skale has a RNG Endpoint
    if (
      block.chainid == uint(1351057110)
      || block.chainid == uint(37084624)
    ) {
      assembly {
        let freemem := mload(0x40)
        let start_addr := add(freemem, 0)
        if iszero(staticcall(gas(), 0x18, 0, 0, start_addr, 32)) {
          invalid()
        }
        salt := mload(freemem)
      }
    }
  }

  function pseudoRandomUint32(uint32 maxValue) internal view returns (uint32) {
    return uint32(pseudoRandom(uint(maxValue)));
  }

  /// @notice Generate pseudo-random uint in the range [0..maxValue) using Solady pseudo-random function
  function nextPrng(LibPRNG.PRNG memory prng, uint maxValue) internal pure returns (uint) {
    return LibPRNG.next(prng) % maxValue;
  }

  /// @notice pseudoRandomUint32 with customizable pseudoRandom()
  function pseudoRandomUint32Flex(
    uint32 maxValue,
    function (uint) internal view returns (uint) random_
  ) internal view returns (uint32) {
    return uint32(random_(uint(maxValue)));
  }

  function pseudoRandomInt32(int32 maxValue) internal view returns (int32) {
    bool neg;
    if (maxValue < 0) {
      neg = true;
      maxValue = - maxValue;
    }
    uint32 v = uint32(pseudoRandom(uint(int(maxValue))));
    return neg
      ? - int32(int(uint(v)))
      : int32(int(uint(v)));
  }

  /// @dev Simplified pseudo-random for minor functionality
  function pseudoRandomWithSeed(uint maxValue, uint seed) internal view returns (uint) {
    if (maxValue == 0) {
      return 0;
    }
    uint salt = genSalt();
    // pseudo random number
    return (uint(keccak256(abi.encodePacked(blockhash(block.number), block.coinbase, block.difficulty, block.number, block.timestamp, tx.gasprice, gasleft(), seed, salt))) % (maxValue + 1));
  }

  /// @dev Simplified pseudo-random for minor functionality, in range
  function pseudoRandomInRange(uint min, uint max) internal view returns (uint) {
    if (min >= max) {
      return max;
    }
    uint r = pseudoRandom(max - min);
    return min + r;
  }

  /// @dev Simplified pseudo-random for minor functionality, in range
  ///      Equal to pseudoRandomInRange(min, max, pseudoRandom)
  function pseudoRandomInRangeFlex(
    uint min,
    uint max,
    function (uint) internal view returns (uint) random_
  ) internal view returns (uint) {
    return min >= max ? max : min + random_(max - min);
  }

  function minusWithZeroFloor(uint a, uint b) internal pure returns (uint){
    if (a <= b) {
      return 0;
    }
    return a - b;
  }

  function minusWithMinFloorI32(int32 a, int32 b) internal pure returns (int32){
    if (int(a) - int(b) < type(int32).min) {
      return type(int32).min;
    }
    return a - b;
  }

  function plusWithMaxFloor32(int32 a, int32 b) internal pure returns (int32){
    if (int(a) + int(b) >= type(int32).max) {
      return type(int32).max;
    }
    return a + b;
  }

  function sqrt(uint x) internal pure returns (uint z) {
    assembly {
    // Start off with z at 1.
      z := 1

    // Used below to help find a nearby power of 2.
      let y := x

    // Find the lowest power of 2 that is at least sqrt(x).
      if iszero(lt(y, 0x100000000000000000000000000000000)) {
        y := shr(128, y) // Like dividing by 2 ** 128.
        z := shl(64, z) // Like multiplying by 2 ** 64.
      }
      if iszero(lt(y, 0x10000000000000000)) {
        y := shr(64, y) // Like dividing by 2 ** 64.
        z := shl(32, z) // Like multiplying by 2 ** 32.
      }
      if iszero(lt(y, 0x100000000)) {
        y := shr(32, y) // Like dividing by 2 ** 32.
        z := shl(16, z) // Like multiplying by 2 ** 16.
      }
      if iszero(lt(y, 0x10000)) {
        y := shr(16, y) // Like dividing by 2 ** 16.
        z := shl(8, z) // Like multiplying by 2 ** 8.
      }
      if iszero(lt(y, 0x100)) {
        y := shr(8, y) // Like dividing by 2 ** 8.
        z := shl(4, z) // Like multiplying by 2 ** 4.
      }
      if iszero(lt(y, 0x10)) {
        y := shr(4, y) // Like dividing by 2 ** 4.
        z := shl(2, z) // Like multiplying by 2 ** 2.
      }
      if iszero(lt(y, 0x8)) {
      // Equivalent to 2 ** z.
        z := shl(1, z)
      }

    // Shifting right by 1 is like dividing by 2.
      z := shr(1, add(z, div(x, z)))
      z := shr(1, add(z, div(x, z)))
      z := shr(1, add(z, div(x, z)))
      z := shr(1, add(z, div(x, z)))
      z := shr(1, add(z, div(x, z)))
      z := shr(1, add(z, div(x, z)))
      z := shr(1, add(z, div(x, z)))

    // Compute a rounded down version of z.
      let zRoundDown := div(x, z)

    // If zRoundDown is smaller, use it.
      if lt(zRoundDown, z) {
        z := zRoundDown
      }
    }
  }

  /*********************************************
 *              PRB-MATH                      *
 *   https://github.com/hifi-finance/prb-math *
 **********************************************/
  /// @notice Calculates the binary logarithm of x.
  ///
  /// @dev Based on the iterative approximation algorithm.
  /// https://en.wikipedia.org/wiki/Binary_logarithm#Iterative_approximation
  ///
  /// Requirements:
  /// - x must be greater than or equal to SCALE, otherwise the result would be negative.
  ///
  /// Caveats:
  /// - The results are nor perfectly accurate to the last decimal,
  ///   due to the lossy precision of the iterative approximation.
  ///
  /// @param x The unsigned 60.18-decimal fixed-point number for which
  ///           to calculate the binary logarithm.
  /// @return result The binary logarithm as an unsigned 60.18-decimal fixed-point number.
  function log2(uint256 x) internal pure returns (uint256 result) {
    if (x < 1e18) revert IAppErrors.TooLowX(x);

    // Calculate the integer part of the logarithm
    // and add it to the result and finally calculate y = x * 2^(-n).
    uint256 n = mostSignificantBit(x / 1e18);

    // The integer part of the logarithm as an unsigned 60.18-decimal fixed-point number.
    // The operation can't overflow because n is maximum 255 and SCALE is 1e18.
    uint256 rValue = n * 1e18;

    // This is y = x * 2^(-n).
    uint256 y = x >> n;

    // If y = 1, the fractional part is zero.
    if (y == 1e18) {
      return rValue;
    }

    // Calculate the fractional part via the iterative approximation.
    // The "delta >>= 1" part is equivalent to "delta /= 2", but shifting bits is faster.
    for (uint256 delta = 5e17; delta > 0; delta >>= 1) {
      y = (y * y) / 1e18;

      // Is y^2 > 2 and so in the range [2,4)?
      if (y >= 2 * 1e18) {
        // Add the 2^(-m) factor to the logarithm.
        rValue += delta;

        // Corresponds to z/2 on Wikipedia.
        y >>= 1;
      }
    }
    return rValue;
  }

  /// @notice Finds the zero-based index of the first one in the binary representation of x.
  /// @dev See the note on msb in the "Find First Set"
  ///      Wikipedia article https://en.wikipedia.org/wiki/Find_first_set
  /// @param x The uint256 number for which to find the index of the most significant bit.
  /// @return msb The index of the most significant bit as an uint256.
  //noinspection NoReturn
  function mostSignificantBit(uint256 x) internal pure returns (uint256 msb) {
    if (x >= 2 ** 128) {
      x >>= 128;
      msb += 128;
    }
    if (x >= 2 ** 64) {
      x >>= 64;
      msb += 64;
    }
    if (x >= 2 ** 32) {
      x >>= 32;
      msb += 32;
    }
    if (x >= 2 ** 16) {
      x >>= 16;
      msb += 16;
    }
    if (x >= 2 ** 8) {
      x >>= 8;
      msb += 8;
    }
    if (x >= 2 ** 4) {
      x >>= 4;
      msb += 4;
    }
    if (x >= 2 ** 2) {
      x >>= 2;
      msb += 2;
    }
    if (x >= 2 ** 1) {
      // No need to shift x any more.
      msb += 1;
    }
  }

}

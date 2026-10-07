// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Full precision floor/ceiling of a*b/d with a 512-bit intermediate product.
/// @dev Adapted for Solidity 0.8 checked arithmetic from Uniswap v3-core FullMath (MIT).
/// Source: https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol
/// Algorithm credit: Remco Bloemen, https://xn--2-umb.com/21/muldiv (MIT).
/// Modular inverse arithmetic intentionally wraps inside unchecked; final result must fit uint256.
library FullMath {
    function mulDiv(uint256 a,uint256 b,uint256 denominator) internal pure returns(uint256 result) {
        unchecked {
            uint256 low; uint256 high;
            assembly ("memory-safe") {
                let mm := mulmod(a,b,not(0))
                low := mul(a,b)
                high := sub(sub(mm,low),lt(mm,low))
            }
            if(high == 0) { require(denominator > 0,"Division by zero"); return low/denominator; }
            require(denominator > high,"Math result overflow");
            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(a,b,denominator)
                high := sub(high,gt(remainder,low))
                low := sub(low,remainder)
            }
            uint256 twos=(~denominator+1)&denominator;
            assembly ("memory-safe") {
                denominator := div(denominator,twos)
                low := div(low,twos)
                twos := add(div(sub(0,twos),twos),1)
            }
            low |= high*twos;
            uint256 inverse=(3*denominator)^2;
            inverse *= 2-denominator*inverse;
            inverse *= 2-denominator*inverse;
            inverse *= 2-denominator*inverse;
            inverse *= 2-denominator*inverse;
            inverse *= 2-denominator*inverse;
            inverse *= 2-denominator*inverse;
            return low*inverse;
        }
    }
    function mulDivUp(uint256 a,uint256 b,uint256 denominator) internal pure returns(uint256 result) {
        result=mulDiv(a,b,denominator);
        if(mulmod(a,b,denominator)>0) { require(result<type(uint256).max,"Math result overflow"); result++; }
    }
}

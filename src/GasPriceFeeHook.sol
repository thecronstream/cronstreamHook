// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

// GasPriceFeeHook dynamically adjusts swap fees based on network gas price.
// High gas  → lower fee  (keeps pool competitive when tx costs are expensive)
// Low gas   → higher fee (captures more value when tx costs are cheap)
contract GasPriceFeeHook is BaseHook {
    using LPFeeLibrary for uint24;

    // Fee bounds — Uniswap v4 fees are in hundredths of a bip (1e6 = 100%)
    uint24 public constant LOW_GAS_FEE  = 3000; // 0.30% — applied when gas is cheap
    uint24 public constant HIGH_GAS_FEE = 500;  // 0.05% — applied when gas is expensive

    // Gas price threshold in wei — above this we consider gas "high"
    uint256 public constant GAS_PRICE_THRESHOLD = 10 gwei;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        uint24 fee = tx.gasprice >= GAS_PRICE_THRESHOLD ? HIGH_GAS_FEE : LOW_GAS_FEE;

        // Return the override fee — LPFeeLibrary.OVERRIDE_FEE_FLAG signals v4 to use our fee
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }
}

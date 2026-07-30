// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {GasPriceFeeHook} from "../src/GasPriceFeeHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

contract GasPriceFeeHookTest is BaseTest {
    GasPriceFeeHook hook;

    function setUp() public {
        deployArtifactsAndLabel();

        // Deploy hook at an address with the beforeSwap flag encoded
        address hookAddress = address(
            uint160(Hooks.BEFORE_SWAP_FLAG)
        );

        deployCodeTo(
            "GasPriceFeeHook.sol:GasPriceFeeHook",
            abi.encode(address(poolManager)),
            hookAddress
        );

        hook = GasPriceFeeHook(hookAddress);
    }

    // When gas price is below threshold, hook should return the low-gas (higher) fee
    function test_lowGasPrice_returnsHigherFee() public {
        vm.txGasPrice(5 gwei); // below 10 gwei threshold

        PoolKey memory key;
        SwapParams memory params;

        vm.prank(address(poolManager));
        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) = hook.beforeSwap(
            address(this),
            key,
            params,
            ""
        );

        assertEq(selector, hook.beforeSwap.selector);
        assertEq(fee & (~LPFeeLibrary.OVERRIDE_FEE_FLAG), uint24(3000));
    }

    // When gas price is at or above threshold, hook should return the high-gas (lower) fee
    function test_highGasPrice_returnsLowerFee() public {
        vm.txGasPrice(15 gwei); // above 10 gwei threshold

        PoolKey memory key;
        SwapParams memory params;

        vm.prank(address(poolManager));
        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) = hook.beforeSwap(
            address(this),
            key,
            params,
            ""
        );

        assertEq(selector, hook.beforeSwap.selector);
        assertEq(fee & (~LPFeeLibrary.OVERRIDE_FEE_FLAG), uint24(500));
    }

    // Hook permissions should only have beforeSwap enabled
    function test_hookPermissions() public view {
        Hooks.Permissions memory perms = hook.getHookPermissions();
        assertTrue(perms.beforeSwap);
        assertFalse(perms.afterSwap);
        assertFalse(perms.beforeInitialize);
        assertFalse(perms.afterAddLiquidity);
    }
}

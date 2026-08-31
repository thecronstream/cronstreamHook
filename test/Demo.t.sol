// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {CronStreamHook} from "../src/CronStreamHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseTest} from "./utils/BaseTest.sol";

// Run with: forge test --match-test test_demo -vv
contract DemoTest is BaseTest {

    CronStreamHook hook;
    MockERC20 usdc;
    address vault;

    uint256 constant REWARD_RATE = 1e12;
    uint128 constant POSITION_SIZE = 1000;

    function setUp() public {
        deployArtifactsAndLabel();

        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = makeAddr("Circle Wallet Vault");

        usdc.mint(vault, 10_000_000e18);

        address hookAddress = address(
            uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        );

        deployCodeTo(
            "CronStreamHook.sol:CronStreamHook",
            abi.encode(address(poolManager), address(usdc), REWARD_RATE),
            hookAddress
        );

        hook = CronStreamHook(hookAddress);
        hook.setRewardVault(vault);

        vm.prank(vault);
        usdc.approve(address(hook), type(uint256).max);
    }

    function test_demo_fullRewardFlow() public {
        address lp1 = makeAddr("LP1");
        address lp2 = makeAddr("LP2");
        PoolKey memory key;

        console.log("=============================================");
        console.log("  CronStreamHook - Live Demo");
        console.log("  Time-Weighted USDC Rewards on Uniswap v4");
        console.log("=============================================");
        console.log("");
        console.log("Same position size. Different commitment.");
        console.log("The hook rewards loyalty, not just capital.");
        console.log("");

        // DAY 0 - LP1 enters
        console.log("[Day 0] LP1 deposits 1000 liquidity");
        _add(lp1, key, int256(uint256(POSITION_SIZE)));

        // DAY 6 - LP2 enters late
        vm.warp(block.timestamp + 6 days);
        console.log("[Day 6] LP2 deposits 1000 liquidity (joins late)");
        _add(lp2, key, int256(uint256(POSITION_SIZE)));

        // DAY 7 - both exit
        vm.warp(block.timestamp + 1 days);
        console.log("[Day 7] Both LPs exit the pool");
        console.log("");

        _remove(lp1, key, int256(uint256(POSITION_SIZE)));
        uint256 reward1 = hook.pendingRewards(lp1);
        console.log("[LP1] stayed 7 days  | pending reward:", reward1);

        _remove(lp2, key, int256(uint256(POSITION_SIZE)));
        uint256 reward2 = hook.pendingRewards(lp2);
        console.log("[LP2] stayed 1 day   | pending reward:", reward2);
        console.log("");

        vm.prank(lp1);
        hook.claimRewards();

        vm.prank(lp2);
        hook.claimRewards();

        console.log("[LP1] USDC balance after claim:", usdc.balanceOf(lp1));
        console.log("[LP2] USDC balance after claim:", usdc.balanceOf(lp2));
        console.log("");
        console.log("LP1 earned more than LP2:", reward1 > reward2);
        console.log("LP1 pending after claim:", hook.pendingRewards(lp1));
        console.log("LP2 pending after claim:", hook.pendingRewards(lp2));
        console.log("=============================================");

        assertGt(reward1, reward2, "LP who stayed longer earns more");
        assertGt(reward1, reward2 * 2, "LP1 earns at least 2x LP2");
        assertEq(hook.pendingRewards(lp1), 0);
        assertEq(hook.pendingRewards(lp2), 0);
    }

    function _add(address lp, PoolKey memory key, int256 liquidity) internal {
        ModifyLiquidityParams memory p = ModifyLiquidityParams({
            tickLower: -60, tickUpper: 60,
            liquidityDelta: liquidity,
            salt: bytes32(0)
        });
        vm.prank(address(poolManager));
        hook.afterAddLiquidity(lp, key, p, BalanceDelta.wrap(0), BalanceDelta.wrap(0), "");
    }

    function _remove(address lp, PoolKey memory key, int256 liquidity) internal {
        ModifyLiquidityParams memory p = ModifyLiquidityParams({
            tickLower: -60, tickUpper: 60,
            liquidityDelta: -liquidity,
            salt: bytes32(0)
        });
        vm.prank(address(poolManager));
        hook.afterRemoveLiquidity(lp, key, p, BalanceDelta.wrap(0), BalanceDelta.wrap(0), "");
    }
}

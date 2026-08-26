// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {CronStreamHook} from "../src/CronStreamHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseTest} from "./utils/BaseTest.sol";

contract CronStreamHookTest is BaseTest {
    using PoolIdLibrary for PoolKey;

    CronStreamHook hook;
    MockERC20 rewardToken;
    address vault;

    uint256 constant REWARD_RATE = 1e12;
    uint128 constant LIQUIDITY    = 1_000;

    function setUp() public {
        deployArtifactsAndLabel();

        rewardToken = new MockERC20("Reward USDC", "rUSDC", 6);
        vault = makeAddr("vault");

        rewardToken.mint(vault, 1_000_000e18);

        address hookAddress = address(
            uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)
        );

        deployCodeTo(
            "CronStreamHook.sol:CronStreamHook",
            abi.encode(address(poolManager), address(rewardToken), REWARD_RATE),
            hookAddress
        );

        hook = CronStreamHook(hookAddress);
        hook.setRewardVault(vault);

        vm.prank(vault);
        rewardToken.approve(address(hook), type(uint256).max);
    }

    // ─── Permissions ──────────────────────────────────────────────────────────

    function test_hookPermissions() public view {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(p.afterAddLiquidity);
        assertTrue(p.afterRemoveLiquidity);
        assertFalse(p.beforeSwap);
        assertFalse(p.afterSwap);
        assertFalse(p.beforeAddLiquidity);
        assertFalse(p.beforeRemoveLiquidity);
        assertFalse(p.beforeInitialize);
        assertFalse(p.afterInitialize);
    }

    // ─── afterAddLiquidity ────────────────────────────────────────────────────

    function test_afterAddLiquidity_recordsEntryTimeAndLiquidity() public {
        address lp = makeAddr("lp");
        PoolKey memory key;
        PoolId poolId = key.toId();

        _addLiquidity(lp, key, int256(uint256(LIQUIDITY)));

        assertEq(hook.lpEntryTime(poolId, _posId(lp)), block.timestamp);
        assertEq(hook.lpLiquidity(poolId, _posId(lp)), LIQUIDITY);
        assertEq(hook.totalLiquidity(poolId), LIQUIDITY);
    }

    function test_afterAddLiquidity_existingPosition_accruesBeforeUpdate() public {
        address lp = makeAddr("lp");
        PoolKey memory key;

        _addLiquidity(lp, key, int256(uint256(LIQUIDITY)));

        vm.warp(block.timestamp + 100);

        // Second add — hook should accrue reward first, then reset clock
        _addLiquidity(lp, key, int256(uint256(LIQUIDITY)));

        // reward = (1000 * 100 * REWARD_RATE) / 1000
        uint256 expectedReward = 100 * REWARD_RATE;
        assertEq(hook.pendingRewards(lp), expectedReward);
    }

    // ─── afterRemoveLiquidity ─────────────────────────────────────────────────

    function test_afterRemoveLiquidity_accruesCorrectReward() public {
        address lp = makeAddr("lp");
        PoolKey memory key;
        PoolId poolId = key.toId();

        _addLiquidity(lp, key, int256(uint256(LIQUIDITY)));

        vm.warp(block.timestamp + 200);

        _removeLiquidity(lp, key, int256(uint256(LIQUIDITY)));

        // reward = (1000 * 200 * REWARD_RATE) / 1000
        uint256 expectedReward = 200 * REWARD_RATE;
        assertEq(hook.pendingRewards(lp), expectedReward);

        // Full exit — state cleared
        assertEq(hook.lpLiquidity(poolId, _posId(lp)), 0);
        assertEq(hook.lpEntryTime(poolId, _posId(lp)), 0);
        assertEq(hook.totalLiquidity(poolId), 0);
    }

    function test_afterRemoveLiquidity_partialExit_resetsEntryClock() public {
        address lp = makeAddr("lp");
        PoolKey memory key;
        PoolId poolId = key.toId();

        _addLiquidity(lp, key, int256(uint256(LIQUIDITY * 2)));

        vm.warp(block.timestamp + 100);

        _removeLiquidity(lp, key, int256(uint256(LIQUIDITY)));

        // reward = (2000 * 100 * REWARD_RATE) / 2000
        uint256 expectedReward = 100 * REWARD_RATE;
        assertEq(hook.pendingRewards(lp), expectedReward);

        // Partial exit — position remains, entry time reset to now
        assertEq(hook.lpLiquidity(poolId, _posId(lp)), LIQUIDITY);
        assertEq(hook.lpEntryTime(poolId, _posId(lp)), block.timestamp);
    }

    // ─── claimRewards ─────────────────────────────────────────────────────────

    function test_claimRewards_transfersFromVaultAndZeroesPending() public {
        address lp = makeAddr("lp");
        PoolKey memory key;

        _addLiquidity(lp, key, int256(uint256(LIQUIDITY)));
        vm.warp(block.timestamp + 100);
        _removeLiquidity(lp, key, int256(uint256(LIQUIDITY)));

        uint256 pending = hook.pendingRewards(lp);
        assertGt(pending, 0);

        vm.prank(lp);
        hook.claimRewards();

        assertEq(rewardToken.balanceOf(lp), pending);
        assertEq(hook.pendingRewards(lp), 0);
    }

    function test_claimRewards_revertsWhenNothingPending() public {
        address lp = makeAddr("lp");
        vm.prank(lp);
        vm.expectRevert("Nothing to claim");
        hook.claimRewards();
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    function test_setRewardVault_onlyOwner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        hook.setRewardVault(makeAddr("newVault"));
    }

    function test_setRewardRate_onlyOwner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        hook.setRewardRate(999);
    }

    // ─── Security tests ───────────────────────────────────────────────────────

    // Same block add and remove — elapsed = 0, reward must be 0, no revert
    function test_security_sameBlock_noRevertNoReward() public {
        address lp = makeAddr("lp");
        PoolKey memory key;

        _addLiquidity(lp, key, int256(uint256(LIQUIDITY)));

        // Remove in the same block — no time has passed
        _removeLiquidity(lp, key, int256(uint256(LIQUIDITY)));

        assertEq(hook.pendingRewards(lp), 0);
    }

    // Tiny LP in a pool dominated by a whale — reward rounds to zero, no revert
    function test_security_precisionLoss_tinyLP_rewardRoundsToZeroGracefully() public {
        address whale = makeAddr("whale");
        address tiny  = makeAddr("tiny");
        PoolKey memory key;

        hook.setRewardRate(1); // 1 token per unit per second — forces floor division

        _addLiquidity(whale, key, 1_000_000);
        _addLiquidity(tiny,  key, 1);

        vm.warp(block.timestamp + 1);

        // reward = (1 * 1 * 1) / 1_000_001 = 0 (floor division)
        _removeLiquidity(tiny, key, 1);

        assertEq(hook.pendingRewards(tiny), 0); // rounds to zero — no revert, no stuck funds
    }

    // Same LP, same pool, two positions with different salts — tracked independently
    function test_security_twoPositions_differentSalts_independentTracking() public {
        address lp = makeAddr("lp");
        PoolKey memory key;
        PoolId poolId = key.toId();

        ModifyLiquidityParams memory paramsA = ModifyLiquidityParams({
            tickLower: -60, tickUpper: 60, liquidityDelta: int256(uint256(LIQUIDITY)), salt: bytes32(0)
        });
        ModifyLiquidityParams memory paramsB = ModifyLiquidityParams({
            tickLower: -60, tickUpper: 60, liquidityDelta: int256(uint256(LIQUIDITY)), salt: bytes32(uint256(1))
        });

        vm.prank(address(poolManager));
        hook.afterAddLiquidity(lp, key, paramsA, BalanceDelta.wrap(0), BalanceDelta.wrap(0), "");

        vm.warp(block.timestamp + 100);

        vm.prank(address(poolManager));
        hook.afterAddLiquidity(lp, key, paramsB, BalanceDelta.wrap(0), BalanceDelta.wrap(0), "");

        bytes32 posIdA = keccak256(abi.encodePacked(lp, int24(-60), int24(60), bytes32(0)));
        bytes32 posIdB = keccak256(abi.encodePacked(lp, int24(-60), int24(60), bytes32(uint256(1))));

        // Position A entry time must not have been overwritten by position B
        assertEq(hook.lpEntryTime(poolId, posIdA), 1); // original timestamp
        assertEq(hook.lpEntryTime(poolId, posIdB), block.timestamp); // B added later
        assertTrue(hook.lpEntryTime(poolId, posIdA) != hook.lpEntryTime(poolId, posIdB));
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    // Matches _positionId() in the contract — default tick range and zero salt
    function _posId(address lp) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(lp, int24(-60), int24(60), bytes32(0)));
    }

    function _addLiquidity(address lp, PoolKey memory key, int256 delta) internal {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: delta,
            salt: bytes32(0)
        });
        vm.prank(address(poolManager));
        hook.afterAddLiquidity(lp, key, params, BalanceDelta.wrap(0), BalanceDelta.wrap(0), "");
    }

    function _removeLiquidity(address lp, PoolKey memory key, int256 delta) internal {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: -delta,
            salt: bytes32(0)
        });
        vm.prank(address(poolManager));
        hook.afterRemoveLiquidity(lp, key, params, BalanceDelta.wrap(0), BalanceDelta.wrap(0), "");
    }

}

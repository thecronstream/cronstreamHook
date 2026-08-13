// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// CronStreamHook — Reward Aggregator for Uniswap v4.
// LPs earn USDC rewards proportional to how long they keep their position active.
// No custody. Rewards come from an external vault funded by the protocol or asset issuers.
contract CronStreamHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;

    // ─── Storage ──────────────────────────────────────────────────────────────

    mapping(PoolId => mapping(address => uint256)) public lpEntryTime;
    mapping(PoolId => mapping(address => uint128)) public lpLiquidity;
    mapping(PoolId => uint128) public totalLiquidity;
    mapping(address => uint256) public pendingRewards;

    address public rewardVault;
    address public rewardToken;
    uint256 public rewardRatePerSecond;

    // ─── Events ───────────────────────────────────────────────────────────────

    event RewardAccrued(address indexed lp, uint256 amount);
    event RewardClaimed(address indexed lp, uint256 amount);
    event VaultUpdated(address newVault);
    event RateUpdated(uint256 newRate);

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(
        IPoolManager _poolManager,
        address _rewardToken,
        uint256 _rewardRatePerSecond
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        rewardToken = _rewardToken;
        rewardRatePerSecond = _rewardRatePerSecond;
    }

    // ─── Hook permissions ─────────────────────────────────────────────────────

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ─── afterAddLiquidity ────────────────────────────────────────────────────

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        uint128 newLiquidity = uint128(uint256(params.liquidityDelta));

        if (lpLiquidity[poolId][sender] > 0) {
            // LP already has a position — accrue reward before resetting their clock
            _accrueReward(poolId, sender);
        }

        lpEntryTime[poolId][sender] = block.timestamp;
        lpLiquidity[poolId][sender] += newLiquidity;
        totalLiquidity[poolId] += newLiquidity;

        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    // ─── afterRemoveLiquidity ─────────────────────────────────────────────────

    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        uint128 removedLiquidity = uint128(uint256(-params.liquidityDelta));

        _accrueReward(poolId, sender);

        lpLiquidity[poolId][sender] -= removedLiquidity;
        totalLiquidity[poolId] -= removedLiquidity;

        if (lpLiquidity[poolId][sender] == 0) {
            delete lpEntryTime[poolId][sender];
        } else {
            lpEntryTime[poolId][sender] = block.timestamp;
        }

        return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    // ─── Internal reward calculation ──────────────────────────────────────────

    function _accrueReward(PoolId poolId, address lp) internal {
        uint256 entryTime = lpEntryTime[poolId][lp];
        if (entryTime == 0 || totalLiquidity[poolId] == 0) return;

        uint256 elapsed = block.timestamp - entryTime;
        uint256 reward = (uint256(lpLiquidity[poolId][lp]) * elapsed * rewardRatePerSecond)
            / uint256(totalLiquidity[poolId]);

        if (reward > 0) {
            pendingRewards[lp] += reward;
            emit RewardAccrued(lp, reward);
        }
    }

    // ─── claimRewards ─────────────────────────────────────────────────────────

    function claimRewards() external {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "Nothing to claim");

        pendingRewards[msg.sender] = 0;
        IERC20(rewardToken).safeTransferFrom(rewardVault, msg.sender, amount);

        emit RewardClaimed(msg.sender, amount);
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    function setRewardVault(address _newVault) external onlyOwner {
        rewardVault = _newVault;
        emit VaultUpdated(_newVault);
    }

    function setRewardRate(uint256 _newRate) external onlyOwner {
        rewardRatePerSecond = _newRate;
        emit RateUpdated(_newRate);
    }
}

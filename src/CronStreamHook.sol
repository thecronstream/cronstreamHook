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

    // Keyed by positionId = keccak256(sender, tickLower, tickUpper, salt)
    // so two positions from the same LP in the same tick range but different salts
    // are tracked independently and don't overwrite each other.
    mapping(PoolId => mapping(bytes32 => uint256)) public lpEntryTime;
    mapping(PoolId => mapping(bytes32 => uint128)) public lpLiquidity;
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
        bytes32 posId = _positionId(sender, params);
        uint128 newLiquidity = uint128(uint256(params.liquidityDelta));

        if (lpLiquidity[poolId][posId] > 0) {
            // Position already exists — accrue reward before resetting the clock
            _accrueReward(poolId, posId, sender);
        }

        lpEntryTime[poolId][posId] = block.timestamp;
        lpLiquidity[poolId][posId] += newLiquidity;
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
        bytes32 posId = _positionId(sender, params);
        uint128 removedLiquidity = uint128(uint256(-params.liquidityDelta));

        _accrueReward(poolId, posId, sender);

        lpLiquidity[poolId][posId] -= removedLiquidity;
        totalLiquidity[poolId] -= removedLiquidity;

        if (lpLiquidity[poolId][posId] == 0) {
            delete lpEntryTime[poolId][posId];
        } else {
            lpEntryTime[poolId][posId] = block.timestamp;
        }

        return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    function _positionId(address sender, ModifyLiquidityParams calldata params)
        internal pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(sender, params.tickLower, params.tickUpper, params.salt));
    }

    function _accrueReward(PoolId poolId, bytes32 posId, address lp) internal {
        uint256 entryTime = lpEntryTime[poolId][posId];
        if (entryTime == 0 || totalLiquidity[poolId] == 0) return;

        uint256 elapsed = block.timestamp - entryTime;
        uint256 reward = (uint256(lpLiquidity[poolId][posId]) * elapsed * rewardRatePerSecond)
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
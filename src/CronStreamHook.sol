// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ─── CronStreamHook ───────────────────────────────────────────────────────────
// Reward Aggregator Hook for Uniswap v4.
//
// LPs who provide liquidity to a whitelisted pool earn USDC rewards
// proportional to how long they keep their position active.
//
// No custody. Funds never leave the PoolManager.
// Rewards come from an external vault funded by the protocol or asset issuers.
// ─────────────────────────────────────────────────────────────────────────────

abstract contract CronStreamHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;

    // ─── Persistent storage ───────────────────────────────────────────────────

    // lpEntryTime — records the block.timestamp when an LP first adds liquidity.
    //               Used to calculate how long they've been in the pool.
    //               Reset to current timestamp if they add more liquidity.
    mapping(PoolId => mapping(address => uint256)) public lpEntryTime;

    // lpLiquidity — tracks how much liquidity each LP currently has per pool.
    //               Written in afterAddLiquidity, reduced in afterRemoveLiquidity.
    mapping(PoolId => mapping(address => uint128)) public lpLiquidity;

    // totalLiquidity — sum of all LP liquidity in a pool.
    //                  Used to calculate each LP's pro-rata reward share.
    mapping(PoolId => uint128) public totalLiquidity;

    // pendingRewards — accumulated reward balance owed to each LP.
    //                  Increases when they remove liquidity, claimable anytime.
    mapping(address => uint256) public pendingRewards;

    // rewardVault — address of the USDC vault that funds LP rewards.
    //               Set by admin. Must have approved this contract to spend USDC.
    address public rewardVault;

    // rewardToken — the ERC20 token distributed as rewards (e.g. USDC).
    address public rewardToken;

    // rewardRatePerSecond — how many reward tokens (in wei) are earned
    //                       per unit of liquidity per second across the pool.
    //                       Set by admin. Adjustable over time.
    uint256 public rewardRatePerSecond;


    // ─── Events ───────────────────────────────────────────────────────────────

    event RewardAccrued(address indexed lp, uint256 amount);
    event RewardClaimed(address indexed lp, uint256 amount);
    event VaultUpdated(address newVault);
    event RateUpdated(uint256 newRate);


    // ─── Constructor ──────────────────────────────────────────────────────────
    // Passes poolManager to BaseHook.
    // Sets the reward token and initial rate.
    // Ownable sets msg.sender as admin.

    constructor ( address onlyOwner, address rewardToken, uint256 rewardRatePerSecond){
         msg.sender ;
         rewardToken;
         rewardRatePerSecond;
         
    }

    modifier onlyOwner() override{
        require(msg.sender , "You are not the Owner mate");
        _;
        
    }


    // ─── getHookPermissions() ─────────────────────────────────────────────────
    // Only two callbacks needed:
    //   afterAddLiquidity    = true  ← record LP entry time and liquidity amount
    //   afterRemoveLiquidity = true  ← calculate time-weighted reward and accrue it
    // All other flags = false.

    function getHookPermissions () public pure override  returns ( Hooks.Permissions memory)
   {
    return Hooks.permissions ({
        afterAddLiquidity: true,
        afterRemoveLiquidity: true
    });
   }

    // ─── afterAddLiquidity ────────────────────────────────────────────────────
    // Fires after an LP successfully deposits liquidity into the pool.
    //
    // What we do:
    //   1. If LP has no existing position — record current timestamp as entry time
    //   2. If LP already has a position — accrue their pending reward first,
    //      then update entry time to now (resets their reward clock)
    //   3. Add the new liquidity delta to lpLiquidity[poolId][sender]
    //   4. Add to totalLiquidity[poolId]
    //
    // Return selector + BalanceDelta(0,0) — we do not modify token balances.

    function afterAddLiquidity(PoolId) public  {
        if msg.sender 
        newLiquidity + lpLiquidity[poolId][msg.sender] = totalLiquidity[poolId];

        returns ()

    }


    // ─── afterRemoveLiquidity ─────────────────────────────────────────────────
    // Fires after an LP withdraws liquidity from the pool.
    //
    // What we do:
    //   1. Calculate time elapsed: block.timestamp - lpEntryTime[poolId][sender]
    //   2. Calculate reward:
    //        reward = (lpLiquidity[poolId][sender] * elapsed * rewardRatePerSecond)
    //                 / totalLiquidity[poolId]
    //   3. Add reward to pendingRewards[sender]
    //   4. Subtract removed liquidity from lpLiquidity and totalLiquidity
    //   5. If LP liquidity hits zero, clear their entry time
    //
    // Emit RewardAccrued(sender, reward)
    // Return selector + BalanceDelta(0,0)


    // ─── claimRewards() ───────────────────────────────────────────────────────
    // Public function — any LP calls this to claim their accumulated rewards.
    //
    // What we do:
    //   1. Read pendingRewards[msg.sender]
    //   2. Set pendingRewards[msg.sender] = 0
    //   3. Transfer reward tokens from rewardVault to msg.sender
    //   4. Emit RewardClaimed(msg.sender, amount)
    //
    // Reverts if pending balance is zero.
    // Reverts if vault has insufficient allowance or balance.

    function claimRewards () public {
     pendingRewards[msg.sender] 

    safeerc
     emit RewardClaimed(msg.sender, amount)
    }


    // ─── setRewardVault() ─────────────────────────────────────────────────────
    // onlyOwner — sets the address of the reward funding vault.
    // Emits VaultUpdated.

    function setRewardVault(address _newvault) public onlyOwner{
        //oldvault = _newvault;
        _newvault = rewardVault;
        emit VaultUpdated( rewardVault);
        
    }


    // ─── setRewardRate() ──────────────────────────────────────────────────────
    // onlyOwner — adjusts the reward rate per second.
    // Emits RateUpdated.
    function setRewardRate (uint256 _rewardrate) public onlyOwner {
        _rewardrate = rewardRatePerSecond;
        emit RateUpdated(rewardRatePerSecond);

    }
}

# CronStreamHook

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Solidity](https://img.shields.io/badge/solidity-0.8.26-lightgrey)](https://soliditylang.org)
[![Built with Foundry](https://img.shields.io/badge/built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh)
[![Tests](https://img.shields.io/badge/tests-12%20passing-brightgreen)](test/)
[![Network](https://img.shields.io/badge/network-Base%20Sepolia-0052FF)](https://sepolia.basescan.org)
[![UHI10](https://img.shields.io/badge/Atrium-UHI10-8B5CF6)](https://atrium.academy)

> Uniswap v4 hooks for streaming USDC rewards to long-duration liquidity providers.

Built by [Adebanjo Abraham](https://github.com/16navigabraham) during the [Atrium Academy UHI10 Hookathon](https://atrium.academy).

---

## Overview

CronStreamHook implements a **time-weighted liquidity mining mechanism** on Uniswap v4. Instead of rewarding LPs based on volume or fee generation alone, it rewards sustained participation — the longer a position stays active, the more USDC it earns.

Rewards are drawn from an external vault (e.g. a Circle Wallet), keeping pool tokens entirely within the Uniswap v4 PoolManager. The hook holds no custody over LP funds at any point.

**Idea credit:** Built on the "Streaming USDC Rewards for Liquidity Providers" concept from the [Atrium Academy Request for Hooks](https://atriumacademy.notion.site/atrium-academy-request-for-hooks) (Circle Hook Ideas). Implementation is original.

---

## Hooks

### `CronStreamHook`

Reward aggregator for Uniswap v4 pools. Tracks per-position entry timestamps and liquidity amounts, accrues time-weighted rewards on each liquidity modification, and allows LPs to claim their USDC balance at any time.

| Callback | Role |
|---|---|
| `afterAddLiquidity` | Records position entry timestamp and liquidity. If position exists, accrues pending reward first before resetting clock. |
| `afterRemoveLiquidity` | Calculates elapsed time, computes time-weighted reward, accrues to claimable balance. Clears state on full exit. |

**Reward formula:**

```
reward = (positionLiquidity × elapsed × rewardRatePerSecond) / totalPoolLiquidity
```

### `GasPriceFeeHook`

Dynamic swap fee adjustment based on network gas price. High gas → lower fee (keeps pool competitive). Low gas → higher fee (captures more value). Implemented for UHI Assignment 2.

---

## Architecture

```
LP calls PositionManager.modifyLiquidity()
        │
        ▼
PoolManager calls hook.afterAddLiquidity()
        │
        ├─ New position?
        │     └─ Write lpEntryTime[poolId][positionId] = block.timestamp
        │        Write lpLiquidity[poolId][positionId] = liquidityDelta
        │        Add to totalLiquidity[poolId]
        │
        └─ Existing position?
              └─ Accrue reward:
                   pendingRewards[lp] += (liquidity × elapsed × rate) / total
                 Reset entry clock to now
                 Add new liquidity delta

LP calls hook.claimRewards()
        └─ Transfer pendingRewards[lp] from rewardVault to LP via safeTransferFrom
           Zero out pendingRewards[lp]
```

**Position isolation:** positions are identified by `keccak256(sender, tickLower, tickUpper, salt)` — not wallet address alone. This prevents state overwrite when the same LP holds multiple positions with different salts in the same tick range.

---

## Security

| Threat | Mitigation |
|---|---|
| **Locked LP funds via revert** | `_accrueReward` returns early when `elapsed == 0` or `totalLiquidity == 0`. Division by zero cannot trigger. |
| **Salt-based position overwrite** | Positions keyed by `positionId = keccak256(sender, tickLower, tickUpper, salt)`, not address. |
| **Precision loss on tiny LPs** | Integer division floors reward to zero without reverting. LP can still remove liquidity — no funds locked. |
| **JIT liquidity abuse** | Same-block add and remove yields zero reward (`elapsed == 0`). Time-weighting naturally filters this. |
| **Unauthorized vault access** | `setRewardVault` and `setRewardRate` are `onlyOwner`. Reward transfer uses `safeTransferFrom` requiring explicit vault approval. |

---

## Partner Integrations

| Partner | Integration | Location |
|---|---|---|
| **Circle USDC** | Reward token distributed to LPs | `src/CronStreamHook.sol` — `rewardToken`, `claimRewards()` |
| **Circle Wallets** | External vault funding LP rewards | `src/CronStreamHook.sol` — `rewardVault`, `setRewardVault()` |

No other partner integrations.

---

## Installation

```bash
git clone https://github.com/thecronstream/cronstreamHook
cd cronstreamHook
forge install
forge build
```

**Requirements:** [Foundry](https://getfoundry.sh) · Solidity 0.8.26 · EVM version: Cancun

---

## Testing

```bash
# Run all tests
forge test -v

# Run with coverage
forge coverage

# Target a specific hook
forge test --match-path test/CronStreamHook.t.sol -v
forge test --match-path test/GasPriceFeeHook.t.sol -v
```

**Coverage — `CronStreamHook.sol`**

| Metric | Coverage |
|---|---|
| Lines | 100% |
| Statements | 97.96% |
| Branches | 85.71% |
| Functions | 100% |

**Test cases (12):**
- Hook permissions
- `afterAddLiquidity` — entry time and liquidity recorded
- `afterAddLiquidity` — existing position accrues before clock reset
- `afterRemoveLiquidity` — correct time-weighted reward
- `afterRemoveLiquidity` — partial exit resets entry clock
- `claimRewards` — transfers from vault, zeroes pending balance
- `claimRewards` — reverts when nothing pending
- `setRewardVault` — owner-gated
- `setRewardRate` — owner-gated
- Security: same-block remove, no revert, zero reward
- Security: precision loss — tiny LP rounds to zero gracefully
- Security: two positions with different salts tracked independently

---

## Deployment

### Base Sepolia

```bash
cp .env.example .env
# Set PRIVATE_KEY and RPC_URL in .env

forge script script/DeployCronStream.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

**Deployed contracts**

| Contract | Address |
|---|---|
| CronStreamHook | TBD |
| Mock USDC (reward token) | TBD |
| Reward Vault | TBD |

---

## Repository Structure

```
src/
  CronStreamHook.sol        Reward aggregator hook
  GasPriceFeeHook.sol       Dynamic fee hook
  ICronStream.sol           Interface
test/
  CronStreamHook.t.sol      Unit + security tests
  GasPriceFeeHook.t.sol     Unit tests
  utils/
    BaseTest.sol
    Deployers.sol
script/
  DeployCronStream.s.sol    Deploy to Base Sepolia
```

---

## Stack

[![Uniswap v4](https://img.shields.io/badge/Uniswap-v4-FF007A)](https://github.com/Uniswap/v4-core)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-uniswap--hooks-4E5EE4)](https://github.com/OpenZeppelin/uniswap-hooks)
[![Base](https://img.shields.io/badge/Base-Sepolia-0052FF)](https://base.org)

| Layer | Stack |
|---|---|
| Smart contracts | Solidity 0.8.26 · Foundry |
| Hook base | OpenZeppelin uniswap-hooks · Uniswap v4-core |
| Reward token | Circle USDC |
| Reward vault | Circle Wallets |
| Target network | Base Sepolia |

---

## License

MIT © [Cronstream Protocol Lab](https://github.com/thecronstream)

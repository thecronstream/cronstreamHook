# CronstreamHook

**Uniswap v4 hooks built by Cronstream Protocol Lab.**

Built during the Atrium Academy Uniswap Hook Incubator (UHI10) cohort.

---

## Hooks

### GasPriceFeeHook
Dynamic fee adjustment based on network gas price.

- High gas price → lower swap fee (keeps pool competitive)
- Low gas price → higher swap fee (captures more value)
- Uses `beforeSwap` to return an override fee via `LPFeeLibrary.OVERRIDE_FEE_FLAG`

### CronStreamHook
Streaming USDC rewards for liquidity providers.

LPs earn USDC rewards proportional to how long they keep their liquidity active. No token custody — funds never leave the PoolManager. Rewards are distributed from an external vault funded by the protocol or asset issuers.

- `afterAddLiquidity` — records LP entry timestamp and liquidity amount per pool
- `afterRemoveLiquidity` — calculates time-weighted reward and accrues it to a claimable balance
- `claimRewards()` — LP pulls accumulated USDC from the external vault via safeTransferFrom
- `setRewardVault()` — owner sets the address of the reward funding wallet
- `setRewardRate()` — owner adjusts the reward emission rate per second

**Idea credit:** This hook builds on the "Streaming USDC Rewards for Liquidity Providers" concept from the [Atrium Academy Request for Hooks](https://atriumacademy.notion.site/atrium-academy-request-for-hooks) (Circle Hook Ideas section). The implementation is original.

---

## How it works

1. LP adds liquidity to a pool that has CronStreamHook attached
2. Hook records their entry timestamp and liquidity amount
3. When the LP removes liquidity, the hook calculates:
   `reward = (lpLiquidity * elapsed * rewardRatePerSecond) / totalLiquidity`
4. Reward is accrued to `pendingRewards[lp]`
5. LP calls `claimRewards()` to receive USDC from the vault

Longer position duration = more rewards. Larger share of the pool = more rewards.

---

## Partner integrations

| Partner | Integration | Location in code |
|---|---|---|
| Circle USDC | Reward token distributed to LPs | `src/CronStreamHook.sol` — `rewardToken`, `claimRewards()` |
| Circle Wallets | External vault that funds LP rewards | `src/CronStreamHook.sol` — `rewardVault`, `setRewardVault()` |

No other partner integrations.

---

## Deployment

Deployed on Base Sepolia testnet.

| Contract | Address |
|---|---|
| CronStreamHook | TBD |
| Mock Reward Token | TBD |
| Reward Vault | TBD |

Frontend demo: TBD

---

## Quick start

```bash
forge install
forge build
forge test
```

---

## Run tests

```bash
# All tests
forge test -v

# Specific hook
forge test --match-path test/GasPriceFeeHook.t.sol -v
forge test --match-path test/CronStreamHook.t.sol -v
```

---

## Repo structure

```
src/
  CronStreamHook.sol   — Reward aggregator hook
  GasPriceFeeHook.sol  — Dynamic fee hook (UHI Assignment 2)
  ICronStream.sol      — Interface
test/
  CronStreamHook.t.sol
  GasPriceFeeHook.t.sol
script/
  Deploy.s.sol         — Deployment script for Base Sepolia
```

---

## Stack

| Layer | Stack |
|---|---|
| Smart contracts | Solidity 0.8.26 · Foundry |
| Hook base | OpenZeppelin uniswap-hooks · Uniswap v4-core |
| Reward token | Circle USDC |
| Reward vault | Circle Wallets |
| Network | Base Sepolia (testnet) |

---

## Links

- **Cronstream Protocol:** https://x.com/cronstream
- **Builder:** [Adebanjo Abraham](https://github.com/16navigabraham)

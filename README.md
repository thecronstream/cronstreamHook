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

LPs earn USDC rewards proportional to how long they keep their liquidity active. No token custody — funds never leave the PoolManager. Rewards are distributed from a Circle Wallet vault funded by the protocol or asset issuers.

- `afterAddLiquidity` — records LP entry timestamp and liquidity amount
- `afterRemoveLiquidity` — calculates time-weighted reward and accrues it
- `claimRewards()` — LP pulls accumulated USDC from the Circle Wallet vault

**Idea credit:** This hook builds on the "Streaming USDC Rewards for Liquidity Providers" concept from the [Atrium Academy Request for Hooks](https://atriumacademy.notion.site/atrium-academy-request-for-hooks) (Circle Hook Ideas section). The implementation is original.

---

## Partner integrations

| Partner | Integration | Location in code |
|---|---|---|
| Circle USDC | Reward token distributed to LPs | `src/CronStreamHook.sol` — `rewardToken`, `claimRewards()` |
| Circle Wallets | External vault that funds LP rewards | `src/CronStreamHook.sol` — `rewardVault` |

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
forge test

# Specific hook
forge test --match-path test/GasPriceFeeHook.t.sol -v
forge test --match-path test/CronStreamHook.t.sol -v
```

---

## Stack

| Layer | Stack |
|---|---|
| Smart contracts | Solidity 0.8.26 · Foundry |
| Hook base | OpenZeppelin uniswap-hooks · Uniswap v4-core |
| Reward token | Circle USDC |
| Reward vault | Circle Wallets |
| Target networks | Base · Unichain |

---

## Links

- **Cronstream Protocol:** https://x.com/cronstream
- **Builder:** [Adebanjo Abraham](https://github.com/16navigabraham)

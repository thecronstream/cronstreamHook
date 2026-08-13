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

### CronStreamHook *(in development)*
Reward Aggregator for Uniswap v4 pools.

LPs earn USDC rewards proportional to how long they keep their liquidity active. No custody — funds never leave the PoolManager. Rewards are distributed from an external vault funded by the protocol or asset issuers.

- `afterAddLiquidity` — records LP entry timestamp and liquidity amount
- `afterRemoveLiquidity` — calculates time-weighted reward and accrues it
- `claimRewards()` — LP calls to withdraw accumulated USDC rewards

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
```

---

## Stack

| Layer | Stack |
|---|---|
| Smart contracts | Solidity 0.8.26 · Foundry |
| Hook base | OpenZeppelin uniswap-hooks · Uniswap v4-core |
| Target networks | Base · Arbitrum One · Unichain |

---

## Links

- **Cronstream Protocol:** https://x.com/cronstream
- **Builder:** [Adebanjo Abraham](https://github.com/16navigabraham)

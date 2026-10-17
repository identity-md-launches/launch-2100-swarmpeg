# Swarmpeg (SWARMPEG)

Swarmpeg is an immutable ERC-20 with a fixed supply. Its constructor mints the entire supply once to the immediate deployer. The implementation uses the vendored OpenZeppelin Contracts 5.1.0 ERC-20 without transfer overrides.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity artifact | `src/Swarmpeg.sol:Swarmpeg` |
| Solidity contract name | `Swarmpeg` |
| Token name | `Swarmpeg` |
| Symbol | `SWARMPEG` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Base-unit supply | `1000000000000000000000000000` (`10^27`) |
| Supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None (`[]`) |
| Deployment value | `0` ETH |
| Initial supply recipient | Constructor `msg.sender` |
| Target launch chain | Ethereum, chain ID `1` |
| Solidity compiler | `0.8.26` |
| EVM target | `cancun` |
| Optimization | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

Deploy the compiled creation bytecode directly, without a proxy or an initialization call. There are no linked libraries or external constructor calls. Under the IdentityMD factory launch, the factory is the immediate deployer and receives all tokens; the caller of the factory and transaction origin receive none from the constructor. A direct deployment instead gives the entire supply to the deploying account.

The launch system handles distribution, pool setup, its manifest, and transactions separately. The token takes no factory, owner, router, distributor, recipient, or oracle address arguments. No allocation is embedded in its constructor. This repository contains one production contract and no application contracts.

For the supplied launch terms, the factory distributes 10% to the swarm distributor, 80% to seed the pool, and 10% to the requester's remainder recipient. The token permits these exact transfers. Those percentages and the pool's fee are launch responsibilities, not token fees or special permissions. The separate manifest step records the launch addresses and economics from the assignment.

## Behavior and assumptions

- The task requests ordinary ERC-20 behavior. Successful `transfer`, `approve`, and `transferFrom` calls return `true`; invalid operations revert with OpenZeppelin's ERC-6093 custom errors.
- There is no additional minting, burning, tax, rebase, pause, blacklist, seizure, ownership, upgrade, or recovery function. The supply stays fixed after construction. The name does not imply a peg mechanism, collateral, or redemption guarantee.
- Transfers deliver the exact amount, including transfers involving contracts. Zero-value transfers and self-transfers are supported and emit `Transfer`. Transfers to the zero address revert, including zero-value transfers.
- `approve` replaces the caller's allowance for a nonzero spender and emits `Approval`. Only an approved spender can transfer another holder's tokens. Even a holder using `transferFrom` on itself needs an allowance.
- Finite allowances decrease when used. `type(uint256).max` is an unlimited allowance and does not decrease. OpenZeppelin 5.1.0 does not emit `Approval` when `transferFrom` spends allowance; integrations should query `allowance` for its current value.
- The contract makes no external calls and invokes no recipient callbacks. Normal ETH payments revert. Tokens sent to this token contract or other contracts unable to move them may be inaccessible; there is no administrator to recover them.

## Build and test

Install Foundry and make Solidity 0.8.26 available in its compiler cache. All Solidity library dependencies are ordinary vendored files in `lib/`; no dependency download, submodule, RPC, environment value, or network access is required to build or run the tests once that compiler is available.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xf6219d0305235a109e0f1a94dc90b3ed26412ce08eb5d51a58b6d819cab83a17 forge test
forge fmt --check
```

`foundry.toml` sets 1,024 runs per fuzz test and 256 invariant runs of up to 64 calls each. It does not override the supplied fuzz seed. Tests have isolated setup, do not read or change environment variables, and need no fork, FFI, or filesystem permissions.

`test/Swarmpeg.t.sol` covers metadata, constructor mint events, CREATE2 factory deployment, exact transfers, approvals, zero amounts, self-transfers, infinite allowances, invalid inputs, unauthorized spending, revert atomicity, absent administrative entry points, runtime restrictions, and token distribution flows. Five parameterized fuzz tests exercise transfer conservation, allowance bounds, and balance failures.

`test/Swarmpeg.invariant.t.sol` generates sequences of transfers, approvals, and delegated transfers across four holders. A separate accounting model checks all balances and allowances, including failed actions, after each step; the sum of balances must always equal the fixed supply.

The local distribution test checks token movements for a distributor, pool manager, and trader. It does not instantiate Uniswap or prove full pool initialization and swaps. The supplied protected launch tests require the separate launch harness and resolved launch configuration; they are inputs for the later independent verification step, not runnable standalone tests in this project.

Dependency sources, versions, archive hashes, and licenses are recorded in [DEPENDENCIES.md](DEPENDENCIES.md). The focused security review and its limits are in [SECURITY_REVIEW.md](SECURITY_REVIEW.md).

## After launch

There are no owner-settable parameters, initialization actions, privileged accounts, or ongoing token maintenance duties.

The launch operator is responsible for deploying the exact compiled artifact, distributing its initial holdings according to the launch terms, verifying the source on the explorer, and checking the resulting metadata, total supply, and factory/distributor/pool/remainder balances. An independent adversarial review belongs before release. This assignment does not broadcast transactions.

Holders control their transfers and allowances. Wallets should display amounts using 18 decimals, request only necessary allowances, and allow revocation with `approve(spender, 0)`. Changing a live nonzero allowance has the standard ERC-20 transaction-ordering race; clients should revoke and confirm before granting a replacement allowance when appropriate. There is no administrative recovery from an incorrect transfer or compromised allowance.

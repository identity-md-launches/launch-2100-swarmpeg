# Swarmpeg test suite

The original deployment, ERC-20, launch-transfer, and fuzz tests remain in
`Swarmpeg.t.sol`. `Swarmpeg.adversarial.t.sol` adds nine boundary/scenario tests
and five fuzz properties covering:

- One-wei transfers and the finite allowance immediately below `uint256.max`.
- Replacing and revoking unlimited approvals, including after balances move away and return.
- Caller identity when `msg.sender` and `tx.origin` differ.
- Self-transfer balance checks and zero-address failures at zero and maximum approvals.
- Splitting an allowance across spends, competing spenders, and retrying a failed spend after funding.
- Keeping approvals attached to their owner when tokens change holders.
- Transferring the entire supply to the token contract without burning it.

`Swarmpeg.invariant.t.sol` extends the existing four-actor handler to eight actions.
It interleaves ordinary transfers, approvals, delegated transfers, prepared spends,
revocations, full-balance transfers, donations to the token, and invalid endpoints.
Expected failures are checked inside the handler; unexpected handler reverts fail the campaign.

After each action, independent ghost balances and allowances must match the token.
The sum of actor balances and tokens held by the token contract must remain exactly
`10^27`, and metadata must remain unchanged. Zero-address balances and allowances
must remain zero. After each sequence, all four actors must still be able to transfer
their entire balances, and the accounting invariant is checked again.

Fuzz tests run 1,024 cases each. The invariant runs 256 sequences of 64 actions.
The suite uses the existing vendored dependencies and requires no RPC, environment
configuration, fork, or additional package installation.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xf6219d0305235a109e0f1a94dc90b3ed26412ce08eb5d51a58b6d819cab83a17 forge test
```

The local suite contains 51 tests. The supplied protected launch checks require the
external launch harness and resolved launch parameters; these tests do not replace
that integration verification.

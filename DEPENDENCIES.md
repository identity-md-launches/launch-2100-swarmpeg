# Vendored dependencies

Dependencies are checked-in source files, not submodules. No installation step is needed for verification. Only the production ERC-20 dependency closure and the test library's `src/` tree are included; upstream development tooling is excluded.

| Dependency | Version | Included files | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | `v5.1.0` | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol` | [MIT](lib/openzeppelin-contracts/LICENSE) |
| Forge Standard Library | `v1.9.7` | `src/` (test-only) | [MIT](lib/forge-std/LICENSE-MIT) / [Apache-2.0](lib/forge-std/LICENSE-APACHE) |

The included upstream files are unmodified. Their mappings are in `remappings.txt`.

Source archives:

- [OpenZeppelin Contracts v5.1.0](https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.1.0), downloaded from `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.1.0`.
  SHA-256: `8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686`.
- [Forge Standard Library v1.9.7](https://github.com/foundry-rs/forge-std/releases/tag/v1.9.7), downloaded from `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`.
  SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.

Solidity 0.8.26 is pinned by version in `foundry.toml`; no compiler binary is distributed. Foundry and the pinned compiler are execution prerequisites supplied by the verification profile.

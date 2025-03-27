# Universal Gasless - Smart Contracts

A smart contract project implementing EIP-7702 for universal gasless transaction execution, enabling EOAs to have
contract-like functionality without requiring gas.

## Overview

The Universal Gasless Delegate is a smart contract system that allows EOAs (Externally Owned Accounts) to delegate
transaction execution to a contract while retaining full control of authorization. This enables users to perform gasless
transactions and access advanced features typically only available to contract accounts.

> **Important:** This contract requires deployment on networks that have activated the Pectra hardfork (and consequently
> Dencun), as it leverages [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) (setting code for an EOA) and
> [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) (transient storage opcodes).

### Key Features

- **Gasless Transactions**: Users can have their transactions commited on chain by third-parties, removing the
  requirement to pay gas fees directly
- **Contract-like Functionality**: EOAs gain access to contract abilities like batched transactions
- **EIP-7702 Compatibility**: Leverages the newest Account Abstraction (Delegation) pattern
- **EIP-7821 Support**: Implements flexible execution modes for single and batch operations
- **Secure Signatures**: Integrates EIP-712 typed data signing for secure authorization
- **Emergency Pause**: Includes kill switch functionality for responding to security incidents

The contract is designed for EOAs to delegate their code execution to it. This pattern results in allowing calls to the
EOA address that will trigger the code in the Delegate contract, while making sure that the authorization of operations
remains in control of the EOA signer.

## Repository Structure

```
universal-gasless-7702-contract/
├── src/                       # Source code directory
│   ├── UniversalGaslessDelegate.sol  # Main contract implementing EIP-7702 delegate
│   ├── KillSwitch.sol                # Emergency pause functionality
│   ├── interface/                    # Contract interfaces
│   │   ├── IERC7821.sol              # Interface for EIP-7821 execution standard
│   │   └── IKillSwitch.sol           # Interface for emergency pause control
│   ├── library/                      # Utility libraries
│   │   ├── LibErrors.sol             # Centralized error definitions
│   │   └── NonceStorageStruct.sol    # Storage structure for nonces
│   └── mixins/                       # Contract components
│       ├── NonceBitmap.sol           # Nonce management for replay protection
│       ├── TokenReceiver.sol         # Support for receiving ERC tokens
│       └── TypedAuthorization.sol    # Typed data hashing for authorizations
└── tests/                     # Test directory
    ├── UniversalGaslessDelegate.t.sol  # Main contract tests
    ├── UniversalGaslessDelegate.paused.t.sol  # Tests for paused state
    ├── UniversalGaslessDelegationHelper.sol   # Helper for delegation tests
    ├── KillSwitch.t.sol               # KillSwitch tests
    ├── UGD.*.t.sol                    # Component-specific tests
    └── mocks/                         # Mock contracts for testing
```

## Prerequisites

- [Bun](https://bun.sh/docs/installation): Foundry defaults to git submodules, but this template uses Node.js packages
  for managing dependencies
- [Forge](https://github.com/foundry-rs/foundry/blob/master/forge): compile, test, fuzz, format, and deploy smart
  contracts
- [Lcov](https://github.com/linux-test-project/lcov) : On macOS, you can install it with Homebrew: `brew install lcov`.

## What's Inside

- [Forge Std](https://github.com/foundry-rs/forge-std): collection of helpful contracts and utilities for testing
- [Prettier](https://github.com/prettier/prettier): code formatter for non-Solidity files
- [Solhint](https://github.com/protofire/solhint): linter for Solidity code

## Getting Started

```sh
$ bun install # install Solhint, Prettier, and other Node.js deps
```

If this is your first time with Foundry, check out the
[installation](https://github.com/foundry-rs/foundry#installation) instructions.

### Features

If you're interested in exploring Foundry in more detail, you should look at the
[Foundry Book](https://book.getfoundry.sh). In particular, you may be interested in reading the
[Writing Tests](https://book.getfoundry.sh/forge/writing-tests.html) tutorial.

### VSCode Integration

This template is IDE agnostic, but for the best user experience, you may want to use it in VSCode alongside Nomic
Foundation's [Solidity extension](https://marketplace.visualstudio.com/items?itemName=NomicFoundation.hardhat-solidity).

For guidance on how to integrate a Foundry project in VSCode, please refer to this
[guide](https://book.getfoundry.sh/config/vscode).

## Installing Dependencies

Foundry typically uses git submodules to manage dependencies, but this template uses Node.js packages.

This is how to install dependencies:

1. Install the dependency using your preferred package manager, e.g. `bun install dependency-name`
   - Use this syntax to install from GitHub: `bun install github:username/repo-name`
2. Add a remapping for the dependency in [remappings.txt](./remappings.txt), e.g.
   `dependency-name=node_modules/dependency-name`

## Writing Tests

To write a new test contract, you start by importing `Test` from `forge-std`, and then you inherit it in your test
contract. Forge Std comes with a pre-instantiated [cheatcodes](https://book.getfoundry.sh/cheatcodes/) environment
accessible via the `vm` property. If you would like to view the logs in the terminal output, you can add the `-vvv` flag
and use [console.log](https://book.getfoundry.sh/faq?highlight=console.log#how-do-i-use-consolelog).

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Compile

Compile the contracts:

```sh
$ forge build
```

### Coverage

Get a test coverage report:

```sh
$ forge coverage
```

### Deploy

> [!NOTE]
>
> This section is only relevant for development purposes.

Deploy to Anvil:

Open a new terminal and run Anvil:

```
$ anvil
```

Then, in another terminal, run the deploy script:

```sh
$ forge script script/Deploy.s.sol --broadcast --fork-url http://localhost:8545
```

For this script to work, you need to have a `MNEMONIC` environment variable set to a valid
[BIP39 mnemonic](https://iancoleman.io/bip39/).

For instructions on how to deploy to a testnet or mainnet, check out the
[Solidity Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting.html) tutorial.

### Format

Format the contracts:

```sh
$ forge fmt
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Lint

Lint the contracts:

```sh
$ bun run lint
```

### Test

Run the tests:

```sh
$ forge test
```

### Test Coverage

Generate test coverage and output result to the terminal:

```sh
$ bun run test:coverage
```

### Test Coverage Report

Generate test coverage with lcov report (you'll have to open the `./coverage/index.html` file in your browser, to do so
simply copy paste the path):

```sh
$ bun run test:coverage:report
```

## Related Efforts

## Licenses

This project is primarily licensed by Fireblocks under AGPLv3.

The following components are included under MIT license:

- `IERC7821.sol` from [Zeppelin Group Ltd](https://github.com/OpenZeppelin/openzeppelin-community-contracts) - Interface
  for the EIP-7821 minimal batch executor standard

For full license texts, see the `./licenses` directory.

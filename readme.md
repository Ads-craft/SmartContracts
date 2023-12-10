# AdCraft Smart Contract

## Overview

This repository contains the smart contract for AdCraft, an innovative platform that leverages blockchain technology to manage and incentivize engagement with ad-related NFTs. The contract is built on the Ethereum blockchain and utilizes the CCIP (Cross-Chain Interoperability Protocol) for communication across different blockchain networks.

## Contract Features

### 1. AdNFT Creation

- Admins can create new AdNFTs, each representing an advertisement, using the `createAdNFT` function.
- The created AdNFTs store engagement data and total staked amount.

### 2. Staking and Rewards

- Users can stake their tokens on specific AdNFTs using the `stakeOnAd` function.
- Stakers earn rewards based on their stake and the engagement score of the associated AdNFT.
- Rewards can be claimed through the `claimRewards` function.

### 3. Chain Compatibility

- The contract supports compatibility checks for different blockchain networks using the `supportedChains` mapping.
- Admins can update chain compatibility using the `updateChainCompatibility` function.

### 4. Cross-Chain Movement

- AdNFTs can be moved to compatible blockchains using the `moveToChain` function.
- This function triggers a CCIP message through the `sendMessagePayNative` function, enabling NFT transfer across chains.

### 5. Oracle Integration

- The contract interacts with a Chainlink Oracle to fetch engagement data for AdNFTs.
- Admins can request engagement data using the `requestEngagementData` function.

### 6. NFT Binding

- Admins can bind AdNFTs for staking using the `bindAdNFT` function.
- Users can check the binding status using the `getBindingStatus` function.

### 7. Pause and Unpause

- The contract can be paused and unpaused by admins using the `pause` and `unpause` functions.

## Usage

### Deploying the Contract

1. Deploy the contract on the Ethereum blockchain.

### Interacting with the Contract

1. Admins can create AdNFTs and bind them using `createAdNFT` and `bindAdNFT`.
2. Stakers can stake tokens on AdNFTs using `stakeOnAd`.
3. Admins can update engagement scores using `updateEngagementScore`.
4. Stakers can claim rewards using `claimRewards`.
5. Admins can move AdNFTs to compatible blockchains using `moveToChain`.
6. Admins can request engagement data from the Chainlink Oracle using `requestEngagementData`.
7. Admins can update chain compatibility using `updateChainCompatibility`.
8. The contract can be paused and unpaused using `pause` and `unpause`.

/////////////////////////////Done////////////////////////////////

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

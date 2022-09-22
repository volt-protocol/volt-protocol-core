# VOLT Protocol System Architecture

## System Components and Architecture

The VOLT system is forked from the FEI protocol codebase and leverages FEI protocol's code as it is audited and battle tested. FEI is pegged to a dollar and thus does not need an oracle to determine the current price of FEI. The reason the FEI system doesn't need an oracle for its own price is because from the system's perspective, 1 FEI equals 1 USD. Because VOLT is not pegged to a dollar, but rather the yield earned on VOLT in underlying venues, it uses a custom system oracle. If there are gains in underlying venues, those will need to be passed onto holders by causing the price of VOLT to increase over time. To support this use case, a custom oracle was built.

## Oracle System

The VOLT Oracle System consists of two contracts. The first is the VoltSystemOracle, which has a monthly rate the Volt system will increase its price by, and then applies that change with a linear interpolation over a 30.42 day timeframe. This contract is ungoverned and immutable. This contract outputs the system redemption price. The next contract is the Oracle Pass Through, which stores a reference to the VoltSystemOracle and passes all calls for the current oracle price through to the VoltSystemOracle. The Oracle Pass Through is governed by a 1 day timelock that is owned by a multisig that has the VOLT core team and advisors as signers.
The Peg Stability Module and all oracles will pull price data from the VoltSystemOracle through a pass through contract called the OraclePassThrough contract. The Oracle pass through contract will pull data directly from the VoltSystemOracle and is in place so that the Peg Stability Module does not need governance actions to upgrade their oracle if logic is changed in the underlying VoltSystemOracle.

## Oracle Pass Through
This contract contains a pointer to the VoltSystemOracle contract and contains two methods which exposes the price by calling the VoltSystemOracle and returning the current system target price. One method `read` turns the VoltSystemOracle's price as a decimal for backwards compatibility with the OracleRef contract and the `getCurrentOraclePrice` method returns the current VoltSystemOracle price as a uint256 scaled up by 1e18.

Only the VOLT timelock can change the address of the VoltSystemOracle in the OraclePassThrough.

## Audits

VOLT has undergone extensive internal review within the TRIBE DAO and has undergone an audit from Zellic and Code4rena.

## Whitepaper
VOLT Protocol [Whitepaper](https://github.com/volt-protocol/whitepaper)

## Dependencies
 Note that this has only been tested on Linux; you may encounter issues running on other operating systems.
 
 - Node v12 or v16 (you can manage Node versions easily with [NVM](https://github.com/nvm-sh/nvm))
 - Foundry

## Installation
 - run `npm install` in the root directory
 - curl -L https://foundry.paradigm.xyz | bash && foundryup

## Usage
 - run `npm run test` to run forge unit tests
 - run `npm run test:integration` to run forge integration tests
 - run `npm run test:hardhat` to run hardhat unit tests
 - run `npm run test:all` to run all tests
 - run `npm run lint` to lint ts files and sol files
 - run `npm lint:all` to lint ts AND js files
 - run `npm run lint:sol` to lint .sol files
 - run `npm run lint:fix` to fix linting errors, if fixable automatically
 - run `npm run prettier:ts` to run prettier and automatically format all ts files
 automatically
 - run `npm run prettier:sol` to run prettier and automatically format all Solidity files
 automatically
 - run `npm run prettier` to run prettier and format all files
 - run `npm run coverage:hardhat` to run smart-contract coverage based off of all tests
 - run `npm run calldata` to generate calldata for a proposal
 - run `npm run check-proposal` to run tests for a specific dao proposal
 - run `npm run compile` to compile smart contracts, if needed

## Deployment
 - Setup your environment variables as found in `.env.example`
 - Copy `.env.example` to `.env`
 - run `npx hardhat node` to to run Hardhat Network locally
 - run `npx hardhat --network <insert network> run scripts/oracleDeploy.ts` to deploy oracle contracts 
 - Fill in `scripts/config.ts` file with newly deployed oracle contracts
 - run `npx hardhat --network <insert network> run scripts/systemDeploy.ts` to deploy the core contracts

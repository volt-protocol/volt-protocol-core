# VOLT Protocol

Smart contract code for VOLT Protocol and the VOLT stablecoin, an inflation resistant stablecoin and unit of account.

VOLT Protocol [Whitepaper](https://github.com/volt-protocol/whitepaper/blob/main/volt.md)

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
 - run `npm run calldata` to generage calldata for a proposal
 - run `npm run check-proposal` to run tests for a specific dao proposal
 - run `npm run compile` to compile smart contracts, if needed

## Documentation
See the [docs](https://docs.fei.money)

## License



# VOLT Protocol System Architecture

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
 - run `npm run compile` to compile smart contracts, if needed
 - run `npm run clean` to clean compiled smart contracts folder, if needed
 - run `npm run test:unit` to run forge unit tests
 - run `npm run test:invariant` to run forge invariant tests
 - run `npm run test:integration` to run forge integration tests
 - run `npm run test:proposals` to run forge proposals tests
 - run `npm run lint` to lint ts files and sol files
 - run `npm run lint:ts` to lint ts files
 - run `npm run lint:ts:fix` to fix linting errors, if fixable automatically
 - run `npm run lint:sol` to lint .sol files
 - run `npm run prettier` to run prettier and detect format errors
 - run `npm run prettier:fix` to run prettier and format all files
 - run `npm run coverage` to generate smart-contract coverage report

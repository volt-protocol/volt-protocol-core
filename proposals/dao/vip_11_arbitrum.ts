import {
  DeployUpgradeFunc,
  NamedAddresses,
  SetupUpgradeFunc,
  TeardownUpgradeFunc,
  ValidateUpgradeFunc
} from '@custom-types/types';
import config from '../../scripts/config';
import { expect } from 'chai';
import { ethers } from 'hardhat';
const { STARTING_ORACLE_PRICE, ORACLE_PERIOD_START_TIME, MONTHLY_CHANGE_RATE_BASIS_POINTS } = config;

/*

Volt Protocol Improvement Proposal #11

Description: Patch in a new system oracle and repoint all PSM's to it

Steps:
  1 - Deploy Volt System Oracle
  2 - Point Oracle Pass Through to New Oracle

*/

const vipNumber = '11';

const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  const VoltSystemOracleFactory = await ethers.getContractFactory('VoltSystemOracle');

  const arbitrumVoltSystemOracle = await VoltSystemOracleFactory.deploy(
    MONTHLY_CHANGE_RATE_BASIS_POINTS,
    ORACLE_PERIOD_START_TIME,
    STARTING_ORACLE_PRICE
  );
  await arbitrumVoltSystemOracle.deployed();

  console.log(`Volt System Oracle ${arbitrumVoltSystemOracle.address}`);

  console.log(`Deployed volt system oracle VIP-${vipNumber}`);
  return {
    arbitrumVoltSystemOracle
  };
};

const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const { arbitrumOraclePassThrough, arbitrumVoltSystemOracle, arbitrumTimelockController } = contracts;

  expect((await arbitrumVoltSystemOracle.oraclePrice()).toString()).to.be.equal(STARTING_ORACLE_PRICE);
  expect((await arbitrumVoltSystemOracle.getCurrentOraclePrice()).toString()).to.be.equal(STARTING_ORACLE_PRICE);
  expect((await arbitrumVoltSystemOracle.periodStartTime()).toString()).to.be.equal(ORACLE_PERIOD_START_TIME);
  expect(Number(await arbitrumVoltSystemOracle.monthlyChangeRateBasisPoints())).to.be.equal(
    MONTHLY_CHANGE_RATE_BASIS_POINTS
  );

  expect(await arbitrumOraclePassThrough.scalingPriceOracle()).to.be.equal(arbitrumVoltSystemOracle.address);
  expect(await arbitrumOraclePassThrough.owner()).to.be.equal(arbitrumTimelockController.address);

  console.log(`Successfully validated VIP-${vipNumber}`);
};

export { deploy, setup, teardown, validate };

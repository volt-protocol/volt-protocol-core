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

Volt Protocol Improvement Proposal #2

Description: Patch in a new system oracle and repoint all PSM's to it

Steps:
  1 - Deploy Volt System Oracle
  2 - Deploy Oracle Pass Through
  3 - Grant ownership of Oracle Pass Through to the timelock
  4 - Point both FEI and USDC PSM to the new OraclePassThrough

*/

const vipNumber = '2';

const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  const { timelockController } = addresses;
  const VoltSystemOracleFactory = await ethers.getContractFactory('VoltSystemOracle');
  const OraclePassThroughFactory = await ethers.getContractFactory('OraclePassThrough');

  const voltSystemOracle = await VoltSystemOracleFactory.deploy(
    MONTHLY_CHANGE_RATE_BASIS_POINTS,
    ORACLE_PERIOD_START_TIME,
    STARTING_ORACLE_PRICE
  );
  await voltSystemOracle.deployed();

  console.log(`Volt System Oracle ${voltSystemOracle.address}`);

  const oraclePassThrough = await OraclePassThroughFactory.deploy(voltSystemOracle.address);
  await oraclePassThrough.deployed();

  console.log(`Oracle Pass Through ${oraclePassThrough.address}`);

  await oraclePassThrough.transferOwnership(timelockController);

  console.log(`Deployed volt system oracle and oracle passthrough VIP-${vipNumber}`);
  return {
    voltSystemOracle,
    oraclePassThrough
  };
};

const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const { oraclePassThrough, voltSystemOracle, feiPriceBoundPSM, usdcPriceBoundPSM, timelockController } = contracts;

  expect(await voltSystemOracle.oraclePrice()).to.be.equal(STARTING_ORACLE_PRICE);
  expect(await voltSystemOracle.getCurrentOraclePrice()).to.be.equal(STARTING_ORACLE_PRICE);
  expect(await voltSystemOracle.periodStartTime()).to.be.equal(ORACLE_PERIOD_START_TIME);
  expect(await voltSystemOracle.monthlyChangeRateBasisPoints()).to.be.equal(MONTHLY_CHANGE_RATE_BASIS_POINTS);
  expect(await oraclePassThrough.scalingPriceOracle()).to.be.equal(voltSystemOracle.address);
  expect(await oraclePassThrough.owner()).to.be.equal(timelockController.address);

  expect(await feiPriceBoundPSM.oracle()).to.be.equal(oraclePassThrough.address);
  expect(await feiPriceBoundPSM.mintFeeBasisPoints()).to.be.equal(0);

  expect(await usdcPriceBoundPSM.oracle()).to.be.equal(oraclePassThrough.address);
  expect(await usdcPriceBoundPSM.mintFeeBasisPoints()).to.be.equal(0);

  console.log(`Successfully validated VIP-${vipNumber}`);
};

export { deploy, setup, teardown, validate };

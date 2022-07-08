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
  1 - Deploy Volt System Oacle
  2 - Deploy Oracle Pass Through
  3 - Grant ownership of Oracle Pass Through to the timelock
  4 - Point both FEI and USDC PSM to the new OraclePassThrough

*/

const vipNumber = '2';

const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  const { arbitrumOptimisticTimelock } = addresses;
  const VoltSystemOracleFactory = await ethers.getContractFactory('VoltSystemOracle');
  const OraclePassThroughFactory = await ethers.getContractFactory('OraclePassThrough');

  const voltSystemOracleArbitrum = await VoltSystemOracleFactory.deploy(
    MONTHLY_CHANGE_RATE_BASIS_POINTS,
    ORACLE_PERIOD_START_TIME,
    STARTING_ORACLE_PRICE
  );
  await voltSystemOracleArbitrum.deployed();

  const oraclePassThroughArbitrum = await OraclePassThroughFactory.deploy(voltSystemOracleArbitrum.address);
  await oraclePassThroughArbitrum.deployed();

  await oraclePassThroughArbitrum.transferOwnership(arbitrumOptimisticTimelock);

  console.log(`Deployed volt system oracle and oracle passthrough VIP-${vipNumber} on Arbitrum`);
  return {
    voltSystemOracleArbitrum,
    oraclePassThroughArbitrum
  };
};

const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const {
    oraclePassThroughArbitrum,
    voltSystemOracleArbitrum,
    arbitrumDAIPSM,
    arbitrumUSDCPSM,
    arbitrumOptimisticTimelock,
    arbitrumCore
  } = contracts;
  const { pcvGuardEOA1, pcvGuardEOA2, pcvGuardRevoked1 } = addresses;

  expect(await arbitrumCore.isGuardian(pcvGuardEOA1)).to.be.true;
  expect(await arbitrumCore.isGuardian(pcvGuardEOA2)).to.be.true;

  const proposerRole = await arbitrumOptimisticTimelock.PROPOSER_ROLE();
  expect(await arbitrumOptimisticTimelock.hasRole(proposerRole, pcvGuardEOA1)).to.be.true;
  expect(await arbitrumOptimisticTimelock.hasRole(proposerRole, pcvGuardEOA2)).to.be.true;
  expect(await arbitrumOptimisticTimelock.hasRole(proposerRole, pcvGuardRevoked1)).to.be.false;

  expect(await voltSystemOracleArbitrum.oraclePrice()).to.be.equal(STARTING_ORACLE_PRICE);
  expect(await voltSystemOracleArbitrum.getCurrentOraclePrice()).to.be.equal(STARTING_ORACLE_PRICE);
  expect(await voltSystemOracleArbitrum.periodStartTime()).to.be.equal(ORACLE_PERIOD_START_TIME);
  expect(await voltSystemOracleArbitrum.monthlyChangeRateBasisPoints()).to.be.equal(MONTHLY_CHANGE_RATE_BASIS_POINTS);
  expect(await oraclePassThroughArbitrum.scalingPriceOracle()).to.be.equal(voltSystemOracleArbitrum.address);
  expect(await oraclePassThroughArbitrum.owner()).to.be.equal(arbitrumOptimisticTimelock.address);

  expect(await arbitrumUSDCPSM.oracle()).to.be.equal(oraclePassThroughArbitrum.address);
  expect(await arbitrumUSDCPSM.mintFeeBasisPoints()).to.be.equal(5);

  expect(await arbitrumDAIPSM.oracle()).to.be.equal(oraclePassThroughArbitrum.address);
  expect(await arbitrumDAIPSM.mintFeeBasisPoints()).to.be.equal(5);

  console.log(`Successfully validated VIP-${vipNumber} on Arbitrum`);
};

export { deploy, setup, teardown, validate };

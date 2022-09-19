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

Volt Protocol Improvement Proposal #12

Description: Create Compound PCV Router and grant it the PCV Controller role

Steps:
  1 - Deploy Compound PCV Router
  2 - Grant newly deployed compound pcv router the PCV Controller role

*/

const vipNumber = '12';

const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  const compoundPCVRouterOracleFactory = await ethers.getContractFactory('CompoundPCVRouter');

  const compoundPCVRouter = await compoundPCVRouterOracleFactory.deploy(
    addresses.core,
    addresses.makerDaiUsdcPSM,
    addresses.daiCompoundPCVDeposit,
    addresses.usdcCompoundPCVDeposit
  );

  await compoundPCVRouter.deployed();

  console.log(`Compound PCV Router ${compoundPCVRouter.address}`);

  console.log(`Deployed Compound PCV Router VIP-${vipNumber}`);
  return {
    compoundPCVRouter
  };
};

const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const { compoundPCVRouter, core } = contracts;

  expect(await core.isPCVController(compoundPCVRouter.address)).to.be.true;

  expect(await compoundPCVRouter.core()).to.be.equal(addresses.core);
  expect(await compoundPCVRouter.USDC()).to.be.equal(addresses.usdc);
  expect(await compoundPCVRouter.DAI()).to.be.equal(addresses.dai);
  expect(await compoundPCVRouter.daiPcvDeposit()).to.be.equal(addresses.daiCompoundPCVDeposit);
  expect(await compoundPCVRouter.usdcPcvDeposit()).to.be.equal(addresses.usdcCompoundPCVDeposit);
  expect(await compoundPCVRouter.daiPSM()).to.be.equal(addresses.makerDaiUsdcPSM);
  expect(await compoundPCVRouter.GEM_JOIN()).to.be.equal(addresses.makerGemJoin);

  console.log(`Successfully validated VIP-${vipNumber}`);
};

export { deploy, setup, teardown, validate };

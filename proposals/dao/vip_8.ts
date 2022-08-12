import hre, { ethers, artifacts } from 'hardhat';
import { expect } from 'chai';
import {
  DeployUpgradeFunc,
  NamedAddresses,
  SetupUpgradeFunc,
  TeardownUpgradeFunc,
  ValidateUpgradeFunc
} from '@custom-types/types';

/*

Timelock Proposal #8

Description:

Steps:
  1 - Pull all FEI from the FEI PSM to the multisg
  2 - Pause redemptions on the FEI PSM
  3 - Transfer all FEI from multisig to the timelock
  4 - Timelock approves router to spend FEI
  5 - Timelock calls router to swap FEI for DAI, DAI proceeds are sent to the DAI PSM
*/

const vipNumber = '8'; // Change me!

// Do any deployments
// This should exclusively include new contract deployments
const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  console.log(`No deploy actions for vip${vipNumber}`);
  return {
    // put returned contract objects here
  };
};

// Do any setup necessary for running the test.
// This could include setting up Hardhat to impersonate accounts,
// ensuring contracts have a specific state, etc.
const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  console.log(`No actions to complete in setup for vip${vipNumber}`);
};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  console.log(`No actions to complete in teardown for vip${vipNumber}`);
};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const { fei, feiPriceBoundPSM } = contracts;

  expect(await feiPriceBoundPSM.redeemPaused()).to.be.true;
  expect(await fei.balanceOf(addresses.feiPriceBoundPSM)).to.equal(0);
};

export { deploy, setup, teardown, validate };

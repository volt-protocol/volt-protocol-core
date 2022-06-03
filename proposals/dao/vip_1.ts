import { expect } from 'chai';
import {
  DeployUpgradeFunc,
  NamedAddresses,
  SetupUpgradeFunc,
  TeardownUpgradeFunc,
  ValidateUpgradeFunc
} from '@custom-types/types';
import { getImpersonatedSigner } from '@test/helpers';

/*

Timelock Proposal #1

Description:

Steps:
  1 - First grant the timelock the governor role by the multisig
  2 - Run script
  3 - Validate state changes

*/

const vipNumber = '1';

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
  const signer = await getImpersonatedSigner(addresses.protocolMultisig);
  await contracts.core.connect(signer).grantGovernor(addresses.optimisticTimelock);
  console.log('setup function run');
};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  console.log(`No actions to complete in teardown for vip${vipNumber}`);
};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const { core, optimisticTimelock } = contracts;

  expect(await core.isGovernor(optimisticTimelock.address)).to.be.true;
  expect(await core.isPCVController(optimisticTimelock.address)).to.be.true;
};

export { deploy, setup, teardown, validate };

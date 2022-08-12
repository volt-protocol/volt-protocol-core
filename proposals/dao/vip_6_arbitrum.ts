import {
  DeployUpgradeFunc,
  NamedAddresses,
  SetupUpgradeFunc,
  TeardownUpgradeFunc,
  ValidateUpgradeFunc
} from '@custom-types/types';
import { expect } from 'chai';

/*

Volt Protocol Improvement Proposal #6

Description: Set all PSM Mint Fees to 0 on Arbitrum

Steps:
  1 - Set mint fee on DAI PSM to 0
  2 - Set mint fee on USDC PSM to 0

*/

const vipNumber = '6';

const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  return {}; /// return empty object to silence typescript error
};

const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const { arbitrumDAIPSM, arbitrumUSDCPSM } = contracts;

  expect(await arbitrumUSDCPSM.mintFeeBasisPoints()).to.be.equal(0);
  expect(await arbitrumUSDCPSM.redeemFeeBasisPoints()).to.be.equal(0);

  expect(await arbitrumDAIPSM.mintFeeBasisPoints()).to.be.equal(0);
  expect(await arbitrumDAIPSM.redeemFeeBasisPoints()).to.be.equal(0);

  console.log(`Successfully validated VIP-${vipNumber} on Arbitrum`);
};

export { deploy, setup, teardown, validate };

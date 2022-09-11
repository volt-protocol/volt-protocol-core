import { ethers } from 'hardhat';
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

Timelock Proposal #10

Description: Create ERC20Allocator, add DAI and USDC psm and compound pcv deposit to the allocator

Steps:
  1 - Deploy ERC20Allocator
  2 - Add DAI and USDC psm and compound pcv deposit to the allocator

*/

const vipNumber = '10';

const bufferCap = ethers.utils.parseEther('500000');
const maxRateLimitPerSecond = ethers.utils.parseEther('100000');
const rateLimitPerSecond = ethers.utils.parseEther('5.78');
const daiTargetBalance = ethers.utils.parseEther('100000');
const usdcTargetBalance = daiTargetBalance.div(1e12);
const daiDecimalsNormalizer = 0;
const usdcDecimalsNormalizer = 12;

// Do any deployments
// This should exclusively include new contract deployments
const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  const erc20AllocatorFactory = await ethers.getContractFactory('ERC20Allocator');

  const erc20Allocator = await erc20AllocatorFactory.deploy(
    addresses.core,
    maxRateLimitPerSecond,
    rateLimitPerSecond,
    bufferCap
  );
  await erc20Allocator.deployed();

  console.log(`\nERC20 Allocator deployed to: ${erc20Allocator.address}`);

  return {
    erc20Allocator
  };
};

// Do any setup necessary for running the test.
// This could include setting up Hardhat to impersonate accounts,
// ensuring contracts have a specific state, etc.
const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  console.log(`No actions to complete in teardown for vip${vipNumber}`);
};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const { erc20Allocator, core, usdcPriceBoundPSM, daiPriceBoundPSM, daiCompoundPCVDeposit, usdcCompoundPCVDeposit } =
    contracts;

  expect(await core.isPCVController(erc20Allocator.address)).to.be.true;
  expect(core.address).to.be.equal(await erc20Allocator.core());
  {
    const [token, targetBalance, decimalsNormalizer] = await erc20Allocator.allPSMs(daiPriceBoundPSM.address);
    const psmAddress = await erc20Allocator.pcvDepositToPSM(daiCompoundPCVDeposit.address);
    console.log('daiCompoundPCVDeposit.address: ', daiCompoundPCVDeposit.address);
    expect(psmAddress).to.be.equal(daiPriceBoundPSM.address);
    expect(token).to.be.equal(addresses.dai);
    expect(daiTargetBalance.toString()).to.be.equal(targetBalance.toString()); /// had to make it a string otherwise typescript threw an error about comparing objects
    expect(decimalsNormalizer.toString()).to.be.equal(daiDecimalsNormalizer.toString());
  }

  {
    const [token, targetBalance, decimalsNormalizer] = await erc20Allocator.allPSMs(usdcPriceBoundPSM.address);
    const psmAddress = await erc20Allocator.pcvDepositToPSM(usdcCompoundPCVDeposit.address);
    expect(psmAddress).to.be.equal(usdcPriceBoundPSM.address);
    expect(token).to.be.equal(addresses.usdc);
    expect(usdcTargetBalance.toString()).to.be.equal(targetBalance.toString()); /// had to make it a string otherwise typescript threw an error about comparing objects
    expect(decimalsNormalizer.toString()).to.be.equal(usdcDecimalsNormalizer.toString());
  }
};

export { deploy, setup, teardown, validate };

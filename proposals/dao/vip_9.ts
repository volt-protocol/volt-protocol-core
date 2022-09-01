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

Timelock Proposal #9

Description: Add DAI, FEI and USDC Compound PCV Deposits to the PCV Guardian

Steps:
  1 - Deploy all Compound PCV Deposits
  2 - Add them to the PCV Guardian whitelist

*/

const vipNumber = '9';

// Do any deployments
// This should exclusively include new contract deployments
const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  const erc20CompoundPCVDepositFactory = await ethers.getContractFactory('ERC20CompoundPCVDeposit');

  const daiCompoundPCVDeposit = await erc20CompoundPCVDepositFactory.deploy(addresses.core, addresses.cDai);
  const feiCompoundPCVDeposit = await erc20CompoundPCVDepositFactory.deploy(addresses.core, addresses.cFei);
  const usdcCompoundPCVDeposit = await erc20CompoundPCVDepositFactory.deploy(addresses.core, addresses.cUsdc);

  await daiCompoundPCVDeposit.deployed();
  await feiCompoundPCVDeposit.deployed();
  await usdcCompoundPCVDeposit.deployed();

  console.log(`\nDAI Compound PCV Deposit deployed to: ${daiCompoundPCVDeposit.address}`);
  console.log(`\nFEI Compound PCV Deposit deployed to: ${feiCompoundPCVDeposit.address}`);
  console.log(`\nUSDC Compound PCV Deposit deployed to: ${usdcCompoundPCVDeposit.address}`);

  return {
    daiCompoundPCVDeposit,
    feiCompoundPCVDeposit,
    usdcCompoundPCVDeposit
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
  const { pcvGuardian, daiCompoundPCVDeposit, feiCompoundPCVDeposit, usdcCompoundPCVDeposit } = contracts;

  /// DAI deposit
  expect(await daiCompoundPCVDeposit.balanceReportedIn()).to.be.equal(addresses.dai);
  expect(await daiCompoundPCVDeposit.token()).to.be.equal(addresses.dai);
  expect(await daiCompoundPCVDeposit.cToken()).to.be.equal(addresses.cDai);
  expect(await daiCompoundPCVDeposit.core()).to.be.equal(addresses.core);

  /// FEI deposit
  expect(await feiCompoundPCVDeposit.balanceReportedIn()).to.be.equal(addresses.fei);
  expect(await feiCompoundPCVDeposit.token()).to.be.equal(addresses.fei);
  expect(await feiCompoundPCVDeposit.cToken()).to.be.equal(addresses.cFei);
  expect(await feiCompoundPCVDeposit.core()).to.be.equal(addresses.core);

  /// USDC deposit
  expect(await usdcCompoundPCVDeposit.balanceReportedIn()).to.be.equal(addresses.usdc);
  expect(await usdcCompoundPCVDeposit.token()).to.be.equal(addresses.usdc);
  expect(await usdcCompoundPCVDeposit.cToken()).to.be.equal(addresses.cUsdc);
  expect(await usdcCompoundPCVDeposit.core()).to.be.equal(addresses.core);

  /// PCV guardian
  expect(await pcvGuardian.isWhitelistAddress(daiCompoundPCVDeposit.address)).to.be.true;
  expect(await pcvGuardian.isWhitelistAddress(usdcCompoundPCVDeposit.address)).to.be.true;
  expect(await pcvGuardian.isWhitelistAddress(feiCompoundPCVDeposit.address)).to.be.true;
};

export { deploy, setup, teardown, validate };

import { expect } from 'chai';
import {
  DeployUpgradeFunc,
  NamedAddresses,
  SetupUpgradeFunc,
  TeardownUpgradeFunc,
  ValidateUpgradeFunc
} from '@custom-types/types';
import config from './../../scripts/config';
import { getImpersonatedSigner } from '@test/helpers';
import { ethers } from 'hardhat';

/*

Timelock Proposal #3

Description:

Steps:
  1 - Send the OTC Escrow contract 10.17m FEI from the timelock
  2 - Wait for TribeDAO to approve
  3 - Swap occurs from TribeDAO Tribal Council timelock

*/

// volt is sent to volt timelock
// fei is sent to tribe dao tribal council timelock

const vipNumber = '3';
const feiAmount = ethers.constants.WeiPerEther.mul(10_170_000);
const { VOLT_SWAP_AMOUNT } = config;

// Do any deployments
// This should exclusively include new contract deployments
const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  const { fei, volt, tribalCouncilTimelock, optimisticTimelock } = addresses;

  const factory = await ethers.getContractFactory('OtcEscrow');
  const otcEscrowRepayment = await factory.deploy(
    tribalCouncilTimelock, // FEI tribal council timelock receives the FEI
    optimisticTimelock, // Volt optimisticTimelock is the recipient of the VOLT
    volt, // transfer VOLT from fei dao timelock to the volt timelock
    fei, // transfer FEI to the FEI DAO timelock
    VOLT_SWAP_AMOUNT, // VOLT DAO receives 10m VOLT
    feiAmount // 10.17m FEI repaid as oracle price was $1.017 USD per VOLT at time of loan
  );
  await otcEscrowRepayment.deployed();

  console.log('OTC deployed to: ', otcEscrowRepayment.address);

  return { otcEscrowRepayment };
};

// transfer FEI from multisig to the timelock for the swap
const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const msigSigner = await getImpersonatedSigner(addresses.protocolMultisig);
  await contracts.fei.connect(msigSigner).transfer(addresses.optimisticTimelock, feiAmount);

  console.log(`setup function run VIP-${vipNumber}`);
};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  console.log(`No actions to complete in teardown for vip${vipNumber}`);
};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const { fei, volt, otcEscrowRepayment, optimisticTimelock } = contracts;
  const { tribalCouncilTimelock } = addresses;

  expect(await fei.balanceOf(otcEscrowRepayment.address)).to.be.equal(feiAmount);
  expect(await otcEscrowRepayment.recipient()).to.be.equal(optimisticTimelock.address);
  expect(await otcEscrowRepayment.beneficiary()).to.be.equal(tribalCouncilTimelock);

  expect(await otcEscrowRepayment.receivedToken()).to.be.equal(volt.address);
  expect(await otcEscrowRepayment.sentToken()).to.be.equal(fei.address);

  expect(await otcEscrowRepayment.sentAmount()).to.be.equal(feiAmount);
  expect(await otcEscrowRepayment.receivedAmount()).to.be.equal(VOLT_SWAP_AMOUNT);
};

export { deploy, setup, teardown, validate };

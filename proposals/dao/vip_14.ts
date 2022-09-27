import { ethers } from 'hardhat';
import { expect } from 'chai';
import {
  DeployUpgradeFunc,
  NamedAddresses,
  SetupUpgradeFunc,
  TeardownUpgradeFunc,
  ValidateUpgradeFunc
} from '@custom-types/types';

/*

Timelock Proposal #14

Description: Creates COMP Sell only PSM

Deployment Steps:
  1 - Deploy Chainlink Oracle Wrapper
  2 - Deploy COMP PegStabilityModule pointing to the Chainlink Oracle Wrapper
  3 - Deploy ERC20Skimmer that can pull all COMP tokens and send them to the COMP PSM
  4 - Add ERC20Skimmer as a PCV Controller

Governance Proposal Steps:
  1 - Add DAI and USDC Compound PCV Deposit to ERC20 Skimmer
  2 - Grant ERC20 Skimmer PCV Controller role
  3 - Disable buying of COMP through the PSM

*/

const vipNumber = '14';

const fauxReservesThreshold = ethers.constants.MaxUint256;
// these variables are currently unused as the PSM doesn't have the ability to mint
const mintLimitPerSecond = ethers.utils.parseEther('10000');
const voltPSMBufferCap = ethers.utils.parseEther('10000000');
const addressOne = '0x0000000000000000000000000000000000000001';

// Do any deployments
// This should exclusively include new contract deployments
const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  const compCompositeChainlinkOracleWrapper = await (
    await ethers.getContractFactory('CompositeChainlinkOracleWrapper')
  ).deploy(addresses.core, addresses.compUsdChainlinkOracle, addresses.oraclePassThrough);

  await compCompositeChainlinkOracleWrapper.deployed();

  const compPSM = await (
    await ethers.getContractFactory('PegStabilityModule')
  ).deploy(
    {
      coreAddress: addresses.core,
      oracleAddress: compCompositeChainlinkOracleWrapper.address, // COMP / VOLT Chainlink Oracle Wrapper
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: 0,
      doInvert: true /// invert the price so that the Oracle and PSM works correctly
    },
    0, // 0 mint fee
    0, // 0 redeem fee
    fauxReservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    addresses.comp,
    addressOne
  );

  await compPSM.deployed();

  const erc20Skimmer = await (
    await ethers.getContractFactory('ERC20Skimmer')
  ).deploy(addresses.core, compPSM.address, addresses.comp);

  await erc20Skimmer.deployed();

  console.log(`\nComp PegStabilityModule deployed to: ${compPSM.address}`);
  console.log(`ChainlinkOracleWrapper deployed to: ${compCompositeChainlinkOracleWrapper.address}`);
  console.log(`ERC20Skimmer deployed to: ${erc20Skimmer.address}`);

  return {
    compPSM,
    compCompositeChainlinkOracleWrapper,
    erc20Skimmer
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
  const { volt, feiPriceBoundPSM, usdcPriceBoundPSM, pcvGuardian, makerRouter, daiPriceBoundPSM } = contracts;
};

export { deploy, setup, teardown, validate };

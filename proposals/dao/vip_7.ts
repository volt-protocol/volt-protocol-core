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

Timelock Proposal #7

Description: Pauses minting on FEI PSM, remove VOLT liquidity from FEI PSM, adds DAI PSM to PCVGuardian whitelist, unpause redemptions on the USDC PSM

Steps:
  1 - Pause Minting on the FEI PSM
  2 - Remove all VOLT from FEI PSM
  3 - Add DAI PSM to whitelisted addresses on PCV Guardian
  4 - Unpause redemptions for USDC PSM

*/

const vipNumber = '7';

const voltFloorPrice = 9_000;
const voltCeilingPrice = 10_000;

const daiReservesThreshold = ethers.constants.MaxUint256;
// these variables are currently unused as the PSM doesn't have the ability to mint
const mintLimitPerSecond = ethers.utils.parseEther('10000');
const voltPSMBufferCap = ethers.utils.parseEther('10000000');
const addressOne = '0x0000000000000000000000000000000000000001';

// Do any deployments
// This should exclusively include new contract deployments
const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  const priceBoundPSM = await (
    await ethers.getContractFactory('PriceBoundPSM')
  ).deploy(
    voltFloorPrice,
    voltCeilingPrice,
    {
      coreAddress: addresses.core,
      oracleAddress: addresses.voltSystemOracle, // OPT
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: 0,
      doInvert: true /// invert the price so that the Oracle and PSM works correctly
    },
    0, // 0 mint fee
    0, // 0 redeem fee
    daiReservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    addresses.dai,
    addressOne
  );

  await priceBoundPSM.deployed();

  console.log(`\nDAI PriceBoundPSM deployed to: ${priceBoundPSM.address}`);

  const makerRouter = await (
    await ethers.getContractFactory('MakerRouter')
  ).deploy(addresses.core, addresses.makerDaiUsdcPSM, addresses.feiDaiFixedPricePSM, addresses.dai, addresses.fei);

  console.log(`\nMaker Router deployed to: ${makerRouter.address}`);

  return {
    priceBoundPSM,
    makerRouter
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
  const { volt, feiPriceBoundPSM, usdcPriceBoundPSM, pcvGuardian, makerRouter, daiPriceBoundPSM } = contracts;

  //  oracle
  expect(await daiPriceBoundPSM.doInvert()).to.be.true;
  expect(await daiPriceBoundPSM.oracle()).to.be.equal(addresses.voltSystemOraclePassThrough);
  expect(await daiPriceBoundPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);
  expect(await daiPriceBoundPSM.isPriceValid()).to.be.true;

  //  volt
  expect(await daiPriceBoundPSM.underlyingToken()).to.be.equal(addresses.dai);
  expect(await daiPriceBoundPSM.volt()).to.be.equal(addresses.volt);

  //  psm params
  expect(await daiPriceBoundPSM.redeemFeeBasisPoints()).to.be.equal(0);
  expect(await daiPriceBoundPSM.decimalNormalizer()).to.be.equal(0);
  expect(await daiPriceBoundPSM.mintFeeBasisPoints()).to.be.equal(0);
  expect(await daiPriceBoundPSM.reservesThreshold()).to.be.equal(daiReservesThreshold);
  expect(await daiPriceBoundPSM.surplusTarget()).to.be.equal(addressOne);
  expect(await daiPriceBoundPSM.rateLimitPerSecond()).to.be.equal(mintLimitPerSecond);
  expect(await daiPriceBoundPSM.buffer()).to.be.equal(voltPSMBufferCap);
  expect(await daiPriceBoundPSM.bufferCap()).to.be.equal(voltPSMBufferCap);

  //  price bound params
  expect(await daiPriceBoundPSM.floor()).to.be.equal(voltFloorPrice);
  expect(await daiPriceBoundPSM.ceiling()).to.be.equal(voltCeilingPrice);

  //  balance check
  expect(await daiPriceBoundPSM.balance()).to.be.equal(0);
  expect(await daiPriceBoundPSM.voltBalance()).to.be.equal(0);

  expect(await volt.balanceOf(feiPriceBoundPSM.address)).to.equal(0);
  expect(await feiPriceBoundPSM.mintPaused()).to.be.true;
  expect(await pcvGuardian.isWhitelistAddress(addresses.daiPriceBoundPSM)).to.be.true;
  expect(await usdcPriceBoundPSM.redeemPaused()).to.be.false;

  expect(await makerRouter.fei()).to.equal(addresses.fei);
  expect(await makerRouter.dai()).to.equal(addresses.dai);
  expect(await makerRouter.daiPSM()).to.equal(addresses.makerDaiUsdcPSM);
  expect(await makerRouter.feiPSM()).to.equal(addresses.feiDaiFixedPricePSM);
  expect(await makerRouter.core()).to.equal(addresses.core);
};

export { deploy, setup, teardown, validate };

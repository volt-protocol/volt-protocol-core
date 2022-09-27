import hre, { ethers, artifacts } from 'hardhat';
import { expect } from 'chai';
import {
  DeployUpgradeFunc,
  NamedAddresses,
  SetupUpgradeFunc,
  TeardownUpgradeFunc,
  ValidateUpgradeFunc
} from '@custom-types/types';
import { VoltV2 } from '@custom-types/contracts';
import { getImpersonatedSigner } from '@test/helpers';

/*

Timelock Proposal #9001

Description:

Steps:
  1 - Deploy New Volt Token
  2 - Deploy new DAI PSM
  3 - Deploy new USDC PSM
  4 - Deploy Token Migrator
  5 - Deploy Migrator Router
*/

const vipNumber = '13';

const voltFloorPrice = 9_000;
const voltCeilingPrice = 10_000;

const voltUsdcFloorPrice = '9000000000000000';
const voltUsdcCeilingPrice = '10000000000000000';

// these variables are currently unused as the PSM doesn't have the ability to mint
const reservesThreshold = ethers.constants.MaxUint256;
const mintLimitPerSecond = ethers.utils.parseEther('10000');
const voltPSMBufferCap = ethers.utils.parseEther('10000000');
const addressOne = '0x0000000000000000000000000000000000000001';

const daiTargetBalance = ethers.utils.parseEther('100000');
const usdcTargetBalance = daiTargetBalance.div(1e12);
const daiDecimalsNormalizer = 0;
const usdcDecimalsNormalizer = 12;

let voltInUsdcPSM = 0;
let voltInDaiPSM = 0;

// Do any deployments
// This should exclusively include new contract deployments
const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  const VoltV2Factory = await ethers.getContractFactory('VoltV2');

  const voltV2 = await VoltV2Factory.deploy(addresses.core);
  await voltV2.deployed();

  console.log(`Volt Toke deployed to: ${voltV2.address}`);

  const voltV2DaiPriceBoundPSM = await (
    await ethers.getContractFactory('PriceBoundPSM')
  ).deploy(
    voltFloorPrice,
    voltCeilingPrice,
    {
      coreAddress: addresses.core,
      oracleAddress: addresses.voltSystemOraclePassThrough, // OPT
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: 0,
      doInvert: true, /// invert the price so that the Oracle and PSM works correctly,
      volt: voltV2.address
    },
    0, // 0 mint fee
    0, // 0 redeem fee
    reservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    addresses.dai,
    addressOne
  );

  await voltV2DaiPriceBoundPSM.deployed();

  console.log(`\nDAI PriceBoundPSM deployed to: ${voltV2DaiPriceBoundPSM.address}`);

  const voltV2UsdcPriceBoundPSM = await (
    await ethers.getContractFactory('PriceBoundPSM')
  ).deploy(
    voltUsdcFloorPrice,
    voltUsdcCeilingPrice,
    {
      coreAddress: addresses.core,
      oracleAddress: addresses.voltSystemOraclePassThrough, // OPT
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: 12,
      doInvert: true, /// invert the price so that the Oracle and PSM works correctly,
      volt: voltV2.address
    },
    0,
    0,
    reservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    addresses.usdc,
    addressOne
  );

  console.log(`\nUSDC PriceBoundPSM deployed to: ${voltV2UsdcPriceBoundPSM.address}`);

  const VoltMigrator = await ethers.getContractFactory('VoltMigrator');
  const voltMigrator = await VoltMigrator.deploy(addresses.core, voltV2.address);
  await voltMigrator.deployed();

  console.log(`\nVolt Migrator deployed to: ${voltMigrator.address}`);

  const MigratorRouter = await ethers.getContractFactory('MigratorRouter');
  const migratorRouter = await MigratorRouter.deploy(
    addresses.core,
    voltV2.address,
    voltV2DaiPriceBoundPSM.address,
    voltV2UsdcPriceBoundPSM.address
  );
  await migratorRouter.deployed();

  console.log(`\nMigrator Router deployed to: ${migratorRouter.address}`);

  return {
    voltV2,
    voltV2DaiPriceBoundPSM,
    voltV2UsdcPriceBoundPSM,
    voltMigrator,
    migratorRouter
  };
};

// Do any setup necessary for running the test.
// This could include setting up Hardhat to impersonate accounts,
// ensuring contracts have a specific state, etc.
const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const { pcvGuardian, volt } = contracts;

  const msgSigner = await getImpersonatedSigner(addresses.protocolMultisig);
  const governorVoltBalanceBeforeUsdc = await volt.balanceOf(msgSigner.address);
  await pcvGuardian.connect(msgSigner).withdrawAllERC20ToSafeAddress(addresses.usdcPriceBoundPSM, addresses.volt);
  const governorVoltBalanceAfterUsdc = await volt.balanceOf(msgSigner.address);

  voltInUsdcPSM = governorVoltBalanceAfterUsdc - governorVoltBalanceBeforeUsdc;

  const governorVoltBalanceBeforeDai = await volt.balanceOf(msgSigner.address);
  await pcvGuardian.connect(msgSigner).withdrawAllERC20ToSafeAddress(addresses.daiPriceBoundPSM, addresses.volt);
  const governorVoltBalanceAfterDai = await volt.balanceOf(msgSigner.address);

  voltInDaiPSM = governorVoltBalanceAfterDai - governorVoltBalanceBeforeDai;

  await volt.connnect(msgSigner).safeTransfer(addresses.daiPriceBoundPSM, voltInUsdcPSM + voltInDaiPSM);
};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  console.log(`No actions to complete in teardown for vip${vipNumber}`);
};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const {
    erc20Allocator,
    PCVGuardian,
    voltV2UsdcPriceBoundPSM,
    voltV2DaiPriceBoundPSM,
    daiCompoundPCVDeposit,
    usdcCompoundPCVDeposit,
    voltV2,
    voltMigrator,
    migratorRouter
  } = contracts;

  expect(PCVGuardian.isWhitelistAddress(voltV2UsdcPriceBoundPSM.address)).to.be.true;
  expect(PCVGuardian.isWhitelistAddress(voltV2DaiPriceBoundPSM.address)).to.be.true;

  expect(voltV2.decimals()).to.equal(18);
  expect(voltV2.symbol()).to.equal('VOLT');
  expect(voltV2.name()).to.equal('Volt');
  expect(voltV2.totalSupply()).to.equal(voltInDaiPSM + voltInUsdcPSM);

  expect(voltMigrator.core()).to.equal(addresses.core);
  expect(voltMigrator.oldVolt()).to.equal(addresses.volt);
  expect(voltMigrator.newVolt()).to.equal(addresses.voltV2);

  expect(migratorRouter.daiPSM()).to.equal(addresses.voltV2DaiPriceBoundPSM);
  expect(migratorRouter.usdcPSM()).to.equal(addresses.voltV2UsdcPriceBoundPSM);
  expect(migratorRouter.voltMigrator()).to.equal(addresses.voltMigrator);
  expect(migratorRouter.oldVolt()).to.equal(addresses.volt);
  expect(migratorRouter.newVolt()).to.equal(addresses.voltV2);

  //  oracle
  expect(await voltV2DaiPriceBoundPSM.doInvert()).to.be.true;
  expect(await voltV2DaiPriceBoundPSM.oracle()).to.be.equal(addresses.voltSystemOraclePassThrough);
  expect(await voltV2DaiPriceBoundPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);
  expect(await voltV2DaiPriceBoundPSM.isPriceValid()).to.be.true;

  //  volt
  expect(await voltV2DaiPriceBoundPSM.underlyingToken()).to.be.equal(addresses.dai);
  expect(await voltV2DaiPriceBoundPSM.volt()).to.be.equal(addresses.volt);

  //  psm params
  expect(await voltV2DaiPriceBoundPSM.redeemFeeBasisPoints()).to.be.equal(0);
  expect(await voltV2DaiPriceBoundPSM.decimalNormalizer()).to.be.equal(0);
  expect(await voltV2DaiPriceBoundPSM.mintFeeBasisPoints()).to.be.equal(0);
  expect(await voltV2DaiPriceBoundPSM.reservesThreshold()).to.be.equal(reservesThreshold);
  expect(await voltV2DaiPriceBoundPSM.surplusTarget()).to.be.equal(addressOne);
  expect(await voltV2DaiPriceBoundPSM.rateLimitPerSecond()).to.be.equal(mintLimitPerSecond);
  expect(await voltV2DaiPriceBoundPSM.buffer()).to.be.equal(voltPSMBufferCap);
  expect(await voltV2DaiPriceBoundPSM.bufferCap()).to.be.equal(voltPSMBufferCap);

  //  oracle
  expect(await voltV2UsdcPriceBoundPSM.doInvert()).to.be.true;
  expect(await voltV2UsdcPriceBoundPSM.oracle()).to.be.equal(addresses.voltSystemOraclePassThrough);
  expect(await voltV2UsdcPriceBoundPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);
  expect(await voltV2UsdcPriceBoundPSM.isPriceValid()).to.be.true;

  //  volt
  expect(await voltV2UsdcPriceBoundPSM.underlyingToken()).to.be.equal(addresses.dai);
  expect(await voltV2UsdcPriceBoundPSM.volt()).to.be.equal(addresses.volt);

  //  psm params
  expect(await voltV2UsdcPriceBoundPSM.redeemFeeBasisPoints()).to.be.equal(0);
  expect(await voltV2UsdcPriceBoundPSM.decimalNormalizer()).to.be.equal(12);
  expect(await voltV2UsdcPriceBoundPSM.mintFeeBasisPoints()).to.be.equal(0);
  expect(await voltV2UsdcPriceBoundPSM.reservesThreshold()).to.be.equal(reservesThreshold);
  expect(await voltV2UsdcPriceBoundPSM.surplusTarget()).to.be.equal(addressOne);
  expect(await voltV2UsdcPriceBoundPSM.rateLimitPerSecond()).to.be.equal(mintLimitPerSecond);
  expect(await voltV2UsdcPriceBoundPSM.buffer()).to.be.equal(voltPSMBufferCap);
  expect(await voltV2UsdcPriceBoundPSM.bufferCap()).to.be.equal(voltPSMBufferCap);

  {
    const [token, targetBalance, decimalsNormalizer] = await erc20Allocator.allPSMs(voltV2DaiPriceBoundPSM.address);
    const psmAddress = await erc20Allocator.pcvDepositToPSM(daiCompoundPCVDeposit.address);
    expect(psmAddress).to.be.equal(voltV2DaiPriceBoundPSM.address);
    expect(token).to.be.equal(addresses.dai);
    expect(daiTargetBalance.toString()).to.be.equal(targetBalance.toString()); /// had to make it a string otherwise typescript threw an error about comparing objects
    expect(decimalsNormalizer.toString()).to.be.equal(daiDecimalsNormalizer.toString());
  }

  {
    const [token, targetBalance, decimalsNormalizer] = await erc20Allocator.allPSMs(voltV2UsdcPriceBoundPSM.address);
    const psmAddress = await erc20Allocator.pcvDepositToPSM(usdcCompoundPCVDeposit.address);
    expect(psmAddress).to.be.equal(voltV2UsdcPriceBoundPSM.address);
    expect(token).to.be.equal(addresses.usdc);
    expect(usdcTargetBalance.toString()).to.be.equal(targetBalance.toString()); /// had to make it a string otherwise typescript threw an error about comparing objects
    expect(decimalsNormalizer.toString()).to.be.equal(usdcDecimalsNormalizer.toString());
  }
};

export { deploy, setup, teardown, validate };

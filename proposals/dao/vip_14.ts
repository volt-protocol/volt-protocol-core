import {
  DeployUpgradeFunc,
  NamedAddresses,
  SetupUpgradeFunc,
  TeardownUpgradeFunc,
  ValidateUpgradeFunc
} from '@custom-types/types';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { assertApproxEq } from '@test/helpers';

/*

Volt Protocol Improvement Proposal #14

Description: 

/// Deployment Steps
/// 1. deploy morpho dai deposit
/// 2. deploy morpho usdc deposit
/// 3. deploy compound pcv router pointed to morpho dai and usdc deposits
/// 4. deploy volt system oracle

Governance Steps:
1. Grant Morpho PCV Router PCV Controller Role
2. Revoke PCV Controller Role from Compound PCV Router
3. Remove Compound DAI Deposit from ERC20Allocator
4. Remove Compound USDC Deposit from ERC20Allocator
5. Add Morpho DAI Deposit to ERC20Allocator
6. Add Morpho USDC Deposit to ERC20Allocator
7. Add USDC and DAI Morpho deposits to the PCV Guardian
8. Point Oracle Pass Through to new oracle address

*/

/// TODO update this to correct start time
let startTime;

const monthlyChangeBasisPoints = 29;

const vipNumber = '14';

const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  startTime = Math.floor(Date.now() / 1000).toString();

  const voltSystemOracle = await ethers.getContractAt('VoltSystemOracle', addresses.voltSystemOracle);

  const currentPrice = await voltSystemOracle.getCurrentOraclePrice();

  const morphoPCVDepositFactory = await ethers.getContractFactory('MorphoCompoundPCVDeposit');
  const compoundPCVRouterFactory = await ethers.getContractFactory('CompoundPCVRouter');
  const voltSystemOracleFactory = await ethers.getContractFactory('VoltSystemOracle');

  const daiMorphoCompoundPCVDeposit = await morphoPCVDepositFactory.deploy(addresses.core, addresses.cDai);
  await daiMorphoCompoundPCVDeposit.deployed();

  const usdcMorphoCompoundPCVDeposit = await morphoPCVDepositFactory.deploy(addresses.core, addresses.cUsdc);
  await usdcMorphoCompoundPCVDeposit.deployed();

  const morphoCompoundPCVRouter = await compoundPCVRouterFactory.deploy(
    addresses.core,
    daiMorphoCompoundPCVDeposit.address,
    usdcMorphoCompoundPCVDeposit.address
  );
  await morphoCompoundPCVRouter.deployed();

  const voltSystemOracle348Bips = await voltSystemOracleFactory.deploy(
    monthlyChangeBasisPoints,
    startTime,
    currentPrice
  );
  await voltSystemOracle348Bips.deployed();

  console.log(`Volt System Oracle deployed ${voltSystemOracle348Bips.address}`);
  console.log(`Morpho Compound PCV Router deployed ${morphoCompoundPCVRouter.address}`);
  console.log(`Morpho Compound DAI PCV Deposit deployed ${daiMorphoCompoundPCVDeposit.address}`);
  console.log(`Morpho Compound USDC PCV Deposit deployed ${usdcMorphoCompoundPCVDeposit.address}`);

  console.log(`Successfully Deployed VIP-${vipNumber}`);
  return {
    voltSystemOracle348Bips,
    daiMorphoCompoundPCVDeposit,
    usdcMorphoCompoundPCVDeposit,
    morphoCompoundPCVRouter
  };
};

const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const {
    core,
    voltSystemOracle,
    oraclePassThrough,
    voltSystemOracle348Bips,
    daiMorphoCompoundPCVDeposit,
    usdcMorphoCompoundPCVDeposit,
    morphoCompoundPCVRouter,
    compoundPCVRouter,
    pcvGuardian,
    erc20Allocator
  } = contracts;

  /// Core address validations
  expect(await daiMorphoCompoundPCVDeposit.core()).to.be.equal(core.address);
  expect(await usdcMorphoCompoundPCVDeposit.core()).to.be.equal(core.address);
  expect(await morphoCompoundPCVRouter.core()).to.be.equal(core.address);

  /// oracle pass through validation
  expect(await oraclePassThrough.scalingPriceOracle()).to.be.equal(voltSystemOracle348Bips.address);

  /// pcv controller validation
  expect(await core.isPCVController(compoundPCVRouter.address)).to.be.false;
  expect(await core.isPCVController(morphoCompoundPCVRouter.address)).to.be.true;

  /// morpho compound PCV Router
  expect(await morphoCompoundPCVRouter.USDC()).to.be.equal(addresses.usdc);
  expect(await morphoCompoundPCVRouter.DAI()).to.be.equal(addresses.dai);
  expect(await morphoCompoundPCVRouter.daiPcvDeposit()).to.be.equal(daiMorphoCompoundPCVDeposit.address);
  expect(await morphoCompoundPCVRouter.usdcPcvDeposit()).to.be.equal(usdcMorphoCompoundPCVDeposit.address);
  expect(await morphoCompoundPCVRouter.daiPSM()).to.be.equal(addresses.makerDaiUsdcPSM);
  expect(await morphoCompoundPCVRouter.GEM_JOIN()).to.be.equal(addresses.makerGemJoin);

  /// pcv deposit validation
  expect(await daiMorphoCompoundPCVDeposit.token()).to.be.equal(addresses.dai);
  expect(await usdcMorphoCompoundPCVDeposit.token()).to.be.equal(addresses.usdc);

  expect(await daiMorphoCompoundPCVDeposit.cToken()).to.be.equal(addresses.cDai);
  expect(await usdcMorphoCompoundPCVDeposit.cToken()).to.be.equal(addresses.cUsdc);

  expect(await daiMorphoCompoundPCVDeposit.MORPHO()).to.be.equal(addresses.morphoCompound);
  expect(await usdcMorphoCompoundPCVDeposit.MORPHO()).to.be.equal(addresses.morphoCompound);

  expect(await daiMorphoCompoundPCVDeposit.LENS()).to.be.equal(addresses.morphoCompoundLens);
  expect(await usdcMorphoCompoundPCVDeposit.LENS()).to.be.equal(addresses.morphoCompoundLens);

  /// pcv guardian validation
  expect(await pcvGuardian.isWhitelistAddress(usdcMorphoCompoundPCVDeposit.address)).to.be.true;
  expect(await pcvGuardian.isWhitelistAddress(daiMorphoCompoundPCVDeposit.address)).to.be.true;

  expect(await pcvGuardian.isWhitelistAddress(addresses.daiCompoundPCVDeposit)).to.be.true;
  expect(await pcvGuardian.isWhitelistAddress(addresses.usdcCompoundPCVDeposit)).to.be.true;

  /// erc20 allocator validation
  expect(await erc20Allocator.pcvDepositToPSM(addresses.usdcCompoundPCVDeposit)).to.be.equal(
    ethers.constants.AddressZero
  );
  expect(await erc20Allocator.pcvDepositToPSM(addresses.daiCompoundPCVDeposit)).to.be.equal(
    ethers.constants.AddressZero
  );

  expect(await erc20Allocator.pcvDepositToPSM(addresses.usdcMorphoCompoundPCVDeposit)).to.be.equal(
    addresses.usdcPriceBoundPSM
  );
  expect(await erc20Allocator.pcvDepositToPSM(addresses.daiMorphoCompoundPCVDeposit)).to.be.equal(
    addresses.daiPriceBoundPSM
  );

  /// volt system oracle validation
  expect((await voltSystemOracle348Bips.periodStartTime()).toString()).to.be.equal(startTime.toString());
  expect((await voltSystemOracle348Bips.monthlyChangeRateBasisPoints()).toString()).to.be.equal(
    monthlyChangeBasisPoints.toString()
  );

  await assertApproxEq(
    await voltSystemOracle348Bips.getCurrentOraclePrice(),
    await voltSystemOracle.getCurrentOraclePrice(),
    0 /// allow 0 bips of deviation
  );

  await assertApproxEq(
    await voltSystemOracle348Bips.oraclePrice(),
    await voltSystemOracle.getCurrentOraclePrice(),
    0 /// allow 0 bips of deviation
  );

  await assertApproxEq(
    await voltSystemOracle348Bips.oraclePrice(),
    await voltSystemOracle.getCurrentOraclePrice(),
    0 /// allow 0 bips of deviation
  );

  await assertApproxEq(
    await voltSystemOracle348Bips.getCurrentOraclePrice(),
    await voltSystemOracle348Bips.oraclePrice(),
    0
  );

  console.log(`Successfully validated VIP-${vipNumber}`);
};

export { deploy, setup, teardown, validate };

import { ethers } from 'hardhat';
import { expect } from 'chai';
import config from './config';
import { Core, NonCustodialPSM, GlobalRateLimitedMinter, ERC20CompoundPCVDeposit } from '@custom-types/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const {
  MAINNET_DEPLOYMENT,
  /// addresses
  FEI,
  POOL_8_FEI,
  ZERO_ADDRESS,
  MULTISIG_ADDRESS,
  ORACLE_PASS_THROUGH_ADDRESS,
  SCALING_PRICE_ORACLE_ADDRESS,
  /// fees
  MINT_FEE_BASIS_POINTS,
  REDEEM_FEE_BASIS_POINTS,
  /// grlm/psm constants
  PSM_BUFFER_CAP,
  MAX_BUFFER_CAP,
  RATE_LIMIT_PER_SECOND,
  MAX_RATE_LIMIT_PER_SECOND,
  GLOBAL_MAX_RATE_LIMIT_PER_SECOND,
  MAX_BUFFER_CAP_MULTI_RATE_LIMITED,
  PER_ADDRESS_MAX_RATE_LIMIT_PER_SECOND,
  DEPLOYER_VOLT_AMOUNT
} = config;

/// ~~~ Core Contracts ~~~

/// 1. Core
/// 2. GlobalRateLimitedMinter
/// 3. PCVDeposit
/// 4. Non Custodial PSM

/// Grant PSM the PCV Controller Role
/// Grant GlobalRateLimitedMinter the Minter Role
/// Give the PSM a rate limited buffer stream in the GlobalRateLimitedMinter

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const CoreFactory = await ethers.getContractFactory('Core');
  const core = await CoreFactory.deploy();
  await core.deployed();
  await core.init();

  const volt = await core.volt();

  const GlobalRateLimitedMinterFactory = await ethers.getContractFactory('GlobalRateLimitedMinter');
  const globalRateLimitedMinter = await GlobalRateLimitedMinterFactory.deploy(
    core.address,
    GLOBAL_MAX_RATE_LIMIT_PER_SECOND,
    PER_ADDRESS_MAX_RATE_LIMIT_PER_SECOND,
    MAX_RATE_LIMIT_PER_SECOND,
    MAX_BUFFER_CAP,
    MAX_BUFFER_CAP_MULTI_RATE_LIMITED
  );
  await globalRateLimitedMinter.deployed();

  let underlyingToken;
  let pcvDeposit;

  if (MAINNET_DEPLOYMENT) {
    console.log('Mainnet Deployment');
    const compoundPCVDepositFactory = await ethers.getContractFactory('ERC20CompoundPCVDeposit');
    pcvDeposit = await compoundPCVDepositFactory.deploy(core.address, POOL_8_FEI);
    underlyingToken = await ethers.getContractAt('ERC20', FEI);
  } else {
    const MockERC20Factory = await ethers.getContractFactory('MockERC20');
    underlyingToken = await MockERC20Factory.deploy();
    await underlyingToken.deployed();

    const MockPCVDepositV2 = await ethers.getContractFactory('MockPCVDepositV2');

    pcvDeposit = await MockPCVDepositV2.deploy(core.address, underlyingToken.address, 0, 0);
    await pcvDeposit.deployed();
  }

  const NonCustodialPSMFactory = await ethers.getContractFactory('NonCustodialPSM');

  const oracleParams = {
    coreAddress: core.address,
    oracleAddress: ORACLE_PASS_THROUGH_ADDRESS,
    backupOracle: ZERO_ADDRESS,
    decimalsNormalizer: 0
  };

  const rateLimitedParams = {
    maxRateLimitPerSecond: MAX_RATE_LIMIT_PER_SECOND,
    rateLimitPerSecond: RATE_LIMIT_PER_SECOND,
    bufferCap: MAX_BUFFER_CAP
  };

  const psmParams = {
    mintFeeBasisPoints: MINT_FEE_BASIS_POINTS,
    redeemFeeBasisPoints: REDEEM_FEE_BASIS_POINTS,
    underlyingToken: underlyingToken.address,
    pcvDeposit: pcvDeposit.address,
    rateLimitedMinter: globalRateLimitedMinter.address
  };

  const nonCustodialPSM = await NonCustodialPSMFactory.deploy(oracleParams, rateLimitedParams, psmParams);
  await nonCustodialPSM.deployed();

  await core.grantPCVController(nonCustodialPSM.address);
  await core.grantMinter(globalRateLimitedMinter.address);

  /// do not replenish minting abilities for PSM or deployer
  await globalRateLimitedMinter.addAddress(nonCustodialPSM.address, 0, PSM_BUFFER_CAP);
  await globalRateLimitedMinter.addAddress(deployer.address, 0, DEPLOYER_VOLT_AMOUNT);
  await globalRateLimitedMinter.mintMaxAllowableVolt(MULTISIG_ADDRESS);

  await core.grantGovernor(MULTISIG_ADDRESS);
  await core.revokeGovernor(deployer.address);

  if (MAINNET_DEPLOYMENT) {
    await validateDeployment(nonCustodialPSM, core, globalRateLimitedMinter, pcvDeposit, deployer);
  }

  console.log('\n ~~~~~ Deployed Contracts Successfully ~~~~~ \n');

  console.log(`Core:                     ${core.address}`);
  console.log(`⚡VOLT⚡:                 ${volt}`);
  console.log(`GlobalRateLimitedMinter:  ${globalRateLimitedMinter.address}`);
  console.log(`UnderlyingToken:          ${underlyingToken.address}`);
  console.log(`MockPCVDepositV2:         ${pcvDeposit.address}`);
  console.log(`Non Custodial PSM:        ${nonCustodialPSM.address}`);
}

async function validateDeployment(
  nonCustodialPSM: NonCustodialPSM,
  core: Core,
  globalRateLimitedMinter: GlobalRateLimitedMinter,
  pcvDeposit: ERC20CompoundPCVDeposit,
  deployer: SignerWithAddress
) {
  const volt = await ethers.getContractAt('Volt', await core.volt());
  /// validate oracle deployment
  const scalingPriceOracle = await ethers.getContractAt('ScalingPriceOracle', SCALING_PRICE_ORACLE_ADDRESS);
  const oraclePassThrough = await ethers.getContractAt('OraclePassThrough', ORACLE_PASS_THROUGH_ADDRESS);

  expect(await oraclePassThrough.scalingPriceOracle()).to.be.equal(SCALING_PRICE_ORACLE_ADDRESS);
  expect(await oraclePassThrough.getCurrentOraclePrice()).to.be.equal(await scalingPriceOracle.getCurrentOraclePrice());

  /// assert that deployer doesn't have governor or any privileged roles
  expect(await core.isGovernor(deployer.address)).to.be.false;
  expect(await core.isPCVController(deployer.address)).to.be.false;
  expect(await core.isMinter(deployer.address)).to.be.false;

  /// ensure GlobalRateLimitedMinter is minter
  expect(await core.isMinter(globalRateLimitedMinter.address)).to.be.true;
  /// ensure Non Custodial PSM is PCV Controller
  expect(await core.isPCVController(nonCustodialPSM.address)).to.be.true;

  expect(await volt.balanceOf(MULTISIG_ADDRESS)).to.be.equal(DEPLOYER_VOLT_AMOUNT);
  /// assert volt and core are properly linked together
  expect(await volt.core()).to.be.equal(core.address);
  expect(await core.volt()).to.be.equal(volt.address);

  /// Non Custodial PSM
  expect(await nonCustodialPSM.underlyingToken()).to.be.equal(FEI);
  expect(await nonCustodialPSM.volt()).to.be.equal(volt.address);
  expect(await nonCustodialPSM.redeemFeeBasisPoints()).to.be.equal(REDEEM_FEE_BASIS_POINTS);
  expect(await nonCustodialPSM.mintFeeBasisPoints()).to.be.equal(MINT_FEE_BASIS_POINTS);
  expect(await nonCustodialPSM.pcvDeposit()).to.be.equal(pcvDeposit.address);
  expect(await nonCustodialPSM.rateLimitedMinter()).to.be.equal(globalRateLimitedMinter.address);
  expect(await nonCustodialPSM.core()).to.be.equal(core.address);
  /// unpaused
  expect(await nonCustodialPSM.paused()).to.be.false;
  expect(await nonCustodialPSM.redeemPaused()).to.be.false;
  expect(await nonCustodialPSM.mintPaused()).to.be.false;

  /// pcvDeposit
  expect(await pcvDeposit.token()).to.be.equal(FEI);
  expect(await pcvDeposit.cToken()).to.be.equal(POOL_8_FEI);
  expect(await pcvDeposit.core()).to.be.equal(core.address);

  /// GlobalRateLimitedMinter
  expect(await globalRateLimitedMinter.core()).to.be.equal(core.address);
  expect((await globalRateLimitedMinter.rateLimitPerAddress(deployer.address)).bufferCap).to.be.equal(
    DEPLOYER_VOLT_AMOUNT
  );
  expect(await globalRateLimitedMinter.individualBuffer(deployer.address)).to.be.equal(0);
  expect(await globalRateLimitedMinter.individualBuffer(nonCustodialPSM.address)).to.be.equal(PSM_BUFFER_CAP);
  expect(await globalRateLimitedMinter.individualMaxRateLimitPerSecond()).to.be.equal(MAX_RATE_LIMIT_PER_SECOND);
  expect(await globalRateLimitedMinter.individualMaxBufferCap()).to.be.equal(MAX_BUFFER_CAP);
  expect(await globalRateLimitedMinter.doPartialAction()).to.be.false;
  expect(await globalRateLimitedMinter.bufferCap()).to.be.equal(MAX_BUFFER_CAP_MULTI_RATE_LIMITED);
  expect(await globalRateLimitedMinter.rateLimitPerSecond()).to.be.equal(PER_ADDRESS_MAX_RATE_LIMIT_PER_SECOND);
  expect(await globalRateLimitedMinter.MAX_RATE_LIMIT_PER_SECOND()).to.be.equal(MAX_RATE_LIMIT_PER_SECOND);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

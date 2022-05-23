import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
import config from './config';
import {
  ArbitrumCore,
  Core,
  OraclePassThrough,
  PCVGuardAdmin,
  PCVGuardian,
  PriceBoundPSM,
  ScalingPriceOracle
} from '@custom-types/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const {
  L2_VOLT,
  L2_DAI,
  L2_DEPLOYMENT, /// deploying to L2 or not

  /// fees
  MINT_FEE_BASIS_POINTS,
  REDEEM_FEE_BASIS_POINTS,

  VOLT_FUSE_PCV_DEPOSIT, /// unused deposit
  L2_PROTOCOL_MULTISIG_ADDRESS,

  /// addresses for PCV Guards
  PCV_GUARD_EOA_1,
  PCV_GUARD_EOA_2,

  /// bls cpi-u inflation data
  L2_PREVIOUS_MONTH,
  L2_CURRENT_MONTH,

  /// L2 chainlink
  STARTING_L2_ORACLE_PRICE,
  ACTUAL_START_TIME,
  L2_JOB_ID,
  L2_CHAINLINK_ORACLE_ADDRESS,
  L2_CHAINLINK_FEE,

  /// Roles
  PCV_GUARD_ROLE,
  PCV_GUARD_ADMIN_ROLE
} = config;

const daiReservesThreshold = ethers.constants.MaxUint256; /// max uint value so that we can never allocate surplus on this PSM to the pcv deposit
const mintLimitPerSecond = ethers.utils.parseEther('0'); /// 0 Volt can be minted per second max
const voltPSMBufferCap = ethers.utils.parseEther('0'); /// 0 Volt max can be minted at a time

/// Oracle price does not need to be scaled up because both tokens have 18 decimals
const voltDAIDecimalsNormalizer = 0;

/// Floor and ceiling are inverted due to oracle price inversion
const voltFloorPrice = 9_000;
const voltCeilingPrice = 10_000;

/// ~~~ Contract Deployment ~~~

/// 1. Core
/// 2. VOLT/DAI PSM
/// 3. PCV Guardian
/// 4. PCV Guard Admin

/// Grant PSM the PCV Controller Role

async function main() {
  /// -------- System Deployment --------

  const deployer = (await ethers.getSigners())[0];

  const CoreFactory = await ethers.getContractFactory('ArbitrumCore');
  const core = await CoreFactory.deploy(L2_VOLT); /// point to bridge token as Volt
  await core.deployed();

  const volt = await core.volt();

  const L2ScalingPriceOracleFactory = await ethers.getContractFactory('L2ScalingPriceOracle');
  const OraclePassThroughFactory = await ethers.getContractFactory('OraclePassThrough');

  const scalingPriceOracle = await L2ScalingPriceOracleFactory.deploy(
    L2_CHAINLINK_ORACLE_ADDRESS,
    L2_JOB_ID,
    L2_CHAINLINK_FEE,
    L2_CURRENT_MONTH,
    L2_PREVIOUS_MONTH,
    ACTUAL_START_TIME,
    STARTING_L2_ORACLE_PRICE
  );
  await scalingPriceOracle.deployed();

  const oraclePassThrough = await OraclePassThroughFactory.deploy(scalingPriceOracle.address);
  await oraclePassThrough.deployed();

  /// -------- Oracle Actions --------

  /// transfer ownership to the multisig
  await oraclePassThrough.transferOwnership(L2_PROTOCOL_MULTISIG_ADDRESS);

  const voltPSMFactory = await ethers.getContractFactory('PriceBoundPSM');

  /// Deploy DAI Peg Stability Module
  /// PSM will trade VOLT between 100 cents and 111 cents. If the Volt price exceeds 111 cents,
  /// the floor price will have to be moved lower as the oracle price is inverted.
  /// If price is outside of this band, the PSM will not allow trades
  const voltPSM = await voltPSMFactory.deploy(
    voltFloorPrice,
    voltCeilingPrice,
    {
      coreAddress: core.address,
      oracleAddress: oraclePassThrough.address, /// OPT
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: voltDAIDecimalsNormalizer,
      doInvert: true /// invert the price so that the Oracle and PSM works correctly
    },
    MINT_FEE_BASIS_POINTS,
    REDEEM_FEE_BASIS_POINTS, /// TODO raise this
    daiReservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    L2_DAI,
    VOLT_FUSE_PCV_DEPOSIT /// intentionally set the PCV deposit as an address that does not exist on l2
    /// any calls to try to allocate surplus will fail, however the reserves threshold is too high
    /// so this call will never be be attempted in the first place
  );

  const PCVGuardian = await ethers.getContractFactory('PCVGuardian');

  /// whitelist psm to withdraw from
  /// safe address is protocol multisig
  const pcvGuardian = await PCVGuardian.deploy(core.address, L2_PROTOCOL_MULTISIG_ADDRESS, [voltPSM.address]);
  await pcvGuardian.deployed();

  const PCVGuardAdmin = await ethers.getContractFactory('PCVGuardAdmin');
  const pcvGuardAdmin = await PCVGuardAdmin.deploy(core.address);
  await pcvGuardAdmin.deployed();

  /// -------- PCV Guardian Actions --------

  // Grant PCV Controller and Guardian Roles to the PCV Guardian Contract
  await core.grantPCVController(pcvGuardian.address);
  await core.grantGuardian(pcvGuardian.address);

  // Create the PCV_GUARD_ADMIN Role and Grant to the PCV Guard Admin Contract
  await core.createRole(PCV_GUARD_ADMIN_ROLE, await core.GOVERN_ROLE());
  await core.grantRole(PCV_GUARD_ADMIN_ROLE, pcvGuardAdmin.address);

  // Create the PCV Guard Role and grant the role to PCV Guards via the PCV Guard Admin contract
  await core.createRole(PCV_GUARD_ROLE, PCV_GUARD_ADMIN_ROLE);
  await pcvGuardAdmin.grantPCVGuardRole(PCV_GUARD_EOA_1);
  await pcvGuardAdmin.grantPCVGuardRole(PCV_GUARD_EOA_2);

  await core.grantGovernor(L2_PROTOCOL_MULTISIG_ADDRESS); /// give multisig the governor role

  console.log('\n ~~~~~ Deployed Contracts Successfully ~~~~~ \n');

  console.log(`⚡Core⚡:                 ${core.address}`);
  console.log(`⚡VOLT⚡:                 ${volt}`);
  console.log(`⚡VOLT PSM⚡:             ${voltPSM.address}`);
  console.log(`⚡PCVGuardian⚡:          ${pcvGuardian.address}`);
  console.log(`⚡PCVGuardAdmin⚡:        ${pcvGuardAdmin.address}`);
  console.log(`⚡OraclePassThrough⚡:    ${oraclePassThrough.address}`);
  console.log(`⚡L2ScalingPriceOracle⚡: ${scalingPriceOracle.address}`);

  if (L2_DEPLOYMENT) {
    await verifyEtherscan(voltPSM.address, core.address, volt, oraclePassThrough.address);
  }

  await validateDeployment(core, pcvGuardian, pcvGuardAdmin, deployer, voltPSM, oraclePassThrough, scalingPriceOracle);
}

async function verifyEtherscan(voltPSM: string, core: string, volt: string, oraclePassThrough: string) {
  const oracleParams = {
    coreAddress: core,
    oracleAddress: oraclePassThrough,
    backupOracle: ethers.constants.AddressZero,
    decimalsNormalizer: 0,
    doInvert: true /// invert the price so that the Oracle and PSM works correctly
  };

  await hre.run('verify:verify', {
    address: voltPSM,

    constructorArguments: [
      voltFloorPrice,
      voltCeilingPrice,
      oracleParams,
      MINT_FEE_BASIS_POINTS,
      REDEEM_FEE_BASIS_POINTS,
      daiReservesThreshold,
      mintLimitPerSecond,
      voltPSMBufferCap,
      L2_DAI,
      VOLT_FUSE_PCV_DEPOSIT
    ]
  });

  await hre.run('verify:verify', {
    address: core,
    constructorArguments: [volt]
  });
}

async function validateDeployment(
  core: ArbitrumCore,
  pcvGuardian: PCVGuardian,
  pcvGuardAdmin: PCVGuardAdmin,
  deployer: SignerWithAddress,
  voltPSM: PriceBoundPSM,
  oraclePassThrough: OraclePassThrough,
  scalingPriceOracle: ScalingPriceOracle
) {
  /// -------- Core Parameter Validation --------

  const volt = await ethers.getContractAt('Volt', await core.volt());

  /// assert that deployer doesn't have governor or any privileged roles
  expect(await core.getRoleMemberCount(await core.GOVERN_ROLE())).to.be.equal(3); // core, multisig and deployer are governor
  expect(await core.getRoleMemberCount(await core.MINTER_ROLE())).to.be.equal(0); // only GRLM is minter
  expect(await core.getRoleMemberCount(await core.PCV_CONTROLLER_ROLE())).to.be.equal(1); // only PCV Guardian is minter

  expect(await core.isGovernor(L2_PROTOCOL_MULTISIG_ADDRESS)).to.be.true;
  expect(await core.isGovernor(deployer.address)).to.be.true;
  expect(await core.isGovernor(core.address)).to.be.true;

  expect(await core.isPCVController(deployer.address)).to.be.false;
  expect(await core.isMinter(deployer.address)).to.be.false;

  /// assert volt and core are properly linked together
  /// on l2, volt is a bridge token so it doesn't have a reference to Core and is not mintable
  expect(await core.volt()).to.be.equal(volt.address);

  expect(await core.isPCVController(pcvGuardian.address)).to.be.true;
  expect(await core.isGuardian(pcvGuardian.address)).to.be.true;

  expect(await core.hasRole(PCV_GUARD_ROLE, PCV_GUARD_EOA_1)).to.be.true;
  expect(await core.hasRole(PCV_GUARD_ROLE, PCV_GUARD_EOA_2)).to.be.true;

  expect(await core.hasRole(PCV_GUARD_ADMIN_ROLE, pcvGuardAdmin.address)).to.be.true;

  /// -------- PCV Guard Admin Parameter Validation --------

  expect(await pcvGuardAdmin.core()).to.be.equal(core.address);

  /// -------- PCV Guardian Parameter Validation --------

  expect(await pcvGuardian.isWhitelistAddress(voltPSM.address)).to.be.true;
  expect(await pcvGuardian.safeAddress()).to.be.equal(L2_PROTOCOL_MULTISIG_ADDRESS);

  /// -------- VOLT/DAI PSM Parameter Validation --------

  ///  oracle
  expect(await voltPSM.doInvert()).to.be.true;
  expect(await voltPSM.oracle()).to.be.equal(oraclePassThrough.address);
  expect(await voltPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);

  ///  volt
  expect(await voltPSM.underlyingToken()).to.be.equal(L2_DAI);
  expect(await voltPSM.volt()).to.be.equal(L2_VOLT);

  ///  psm params
  expect(await voltPSM.redeemFeeBasisPoints()).to.be.equal(REDEEM_FEE_BASIS_POINTS); /// 0 basis points
  expect(await voltPSM.mintFeeBasisPoints()).to.be.equal(MINT_FEE_BASIS_POINTS); /// 30 basis points
  expect(await voltPSM.reservesThreshold()).to.be.equal(daiReservesThreshold);
  expect(await voltPSM.surplusTarget()).to.be.equal(VOLT_FUSE_PCV_DEPOSIT);
  expect(await voltPSM.rateLimitPerSecond()).to.be.equal(mintLimitPerSecond);
  expect(await voltPSM.buffer()).to.be.equal(voltPSMBufferCap);
  expect(await voltPSM.bufferCap()).to.be.equal(voltPSMBufferCap);

  ///  price bound params
  expect(await voltPSM.floor()).to.be.equal(voltFloorPrice);
  expect(await voltPSM.ceiling()).to.be.equal(voltCeilingPrice);
  expect(await voltPSM.isPriceValid()).to.be.true;

  ///  balance check
  expect(await voltPSM.balance()).to.be.equal(0);
  expect(await voltPSM.voltBalance()).to.be.equal(0);

  /// -------- OraclePassThrough/ScalingPriceOracle Parameter Validation --------

  expect(await scalingPriceOracle.oraclePrice()).to.be.equal(STARTING_L2_ORACLE_PRICE);
  expect(await scalingPriceOracle.startTime()).to.be.equal(ACTUAL_START_TIME);

  expect(await scalingPriceOracle.currentMonth()).to.be.equal(L2_CURRENT_MONTH);
  expect(await scalingPriceOracle.previousMonth()).to.be.equal(L2_PREVIOUS_MONTH);
  expect(await scalingPriceOracle.monthlyChangeRateBasisPoints()).to.be.equal(55);

  expect(await oraclePassThrough.scalingPriceOracle()).to.be.equal(scalingPriceOracle.address);
  expect(await oraclePassThrough.owner()).to.be.equal(L2_PROTOCOL_MULTISIG_ADDRESS);
  expect(await oraclePassThrough.getCurrentOraclePrice()).to.be.equal(await scalingPriceOracle.getCurrentOraclePrice());

  console.log(`\n ~~~~~ Verified Contracts Successfully ~~~~~ \n`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

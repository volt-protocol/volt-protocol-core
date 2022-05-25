import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
import config from './config';
import {
  L2Core,
  Core,
  OraclePassThrough,
  PCVGuardAdmin,
  PCVGuardian,
  PriceBoundPSM,
  ScalingPriceOracle
} from '@custom-types/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const {
  L2_ARBITRUM_VOLT,
  L2_DAI,
  L2_ARBITRUM_USDC,
  L2_DEPLOYMENT, /// deploying to L2 or not

  /// fees
  MINT_FEE_BASIS_POINTS,
  L2_REDEEM_FEE_BASIS_POINTS,

  VOLT_FUSE_PCV_DEPOSIT, /// unused deposit
  L2_ARBITRUM_PROTOCOL_MULTISIG_ADDRESS,

  /// addresses for PCV Guards
  PCV_GUARD_EOA_1,
  PCV_GUARD_EOA_2,

  /// bls cpi-u inflation data
  L2_ARBITRUM_PREVIOUS_MONTH,
  L2_ARBITRUM_CURRENT_MONTH,

  /// L2 chainlink
  STARTING_L2_ORACLE_PRICE,
  ACTUAL_START_TIME,
  L2_ARBITRUM_JOB_ID,
  L2_ARBITRUM_CHAINLINK_ORACLE_ADDRESS,
  L2_ARBITRUM_CHAINLINK_FEE,

  /// Roles
  PCV_GUARD_ROLE,
  PCV_GUARD_ADMIN_ROLE
} = config;

const reservesThreshold = ethers.constants.MaxUint256; /// max uint value so that we can never allocate surplus on this PSM to the pcv deposit
const mintLimitPerSecond = ethers.utils.parseEther('0'); /// No Volt can be minted
const voltPSMBufferCap = ethers.utils.parseEther('0'); /// No Volt can be minted

/// Oracle price does not need to be scaled up because both tokens have 18 decimals
const voltDAIDecimalsNormalizer = 0;

/// Oracle price gets scaled up by 1e12 to account for the differences in decimals of USDC and VOLT.
/// USDC has 6 decimals while Volt has 12, thus creating a difference that has to be normalized
const voltUSDCDecimalsNormalizer = 12;

/// Floor and ceiling are inverted due to oracle price inversion
const voltDAIFloorPrice = 9_000; /// actually ceiling price, which is $1.11
const voltDAICeilingPrice = 10_000; /// actually floor price, which is $1.00

/// Need to scale up price of floor and ceiling by 1e12 to account for decimal normalizer that is factored into oracle price
const voltUSDCFloorPrice = '9000000000000000';
const voltUSDCCeilingPrice = '10000000000000000';

/// ~~~ Contract Deployment ~~~

/// 1. Core
/// 2. Scaling Price Oracle
/// 3. Oracle Pass Through
/// 4. VOLT/DAI PSM
/// 5. PCV Guardian
/// 6. PCV Guard Admin

/// Grant PSM the PCV Controller Role

async function main() {
  /// -------- System Deployment --------

  const deployer = (await ethers.getSigners())[0];

  const CoreFactory = await ethers.getContractFactory('L2Core');
  const core = await CoreFactory.deploy(L2_ARBITRUM_VOLT); /// point to bridge token as Volt
  await core.deployed();

  const volt = await core.volt();

  const L2ScalingPriceOracleFactory = await ethers.getContractFactory('L2ScalingPriceOracle');
  const OraclePassThroughFactory = await ethers.getContractFactory('OraclePassThrough');

  const scalingPriceOracle = await L2ScalingPriceOracleFactory.deploy(
    L2_ARBITRUM_CHAINLINK_ORACLE_ADDRESS,
    L2_ARBITRUM_JOB_ID,
    L2_ARBITRUM_CHAINLINK_FEE,
    L2_ARBITRUM_CURRENT_MONTH,
    L2_ARBITRUM_PREVIOUS_MONTH,
    ACTUAL_START_TIME,
    STARTING_L2_ORACLE_PRICE
  );
  await scalingPriceOracle.deployed();

  const oraclePassThrough = await OraclePassThroughFactory.deploy(scalingPriceOracle.address);
  await oraclePassThrough.deployed();

  /// -------- Oracle Actions --------

  /// transfer ownership to the multisig
  await oraclePassThrough.transferOwnership(L2_ARBITRUM_PROTOCOL_MULTISIG_ADDRESS);

  const voltPSMFactory = await ethers.getContractFactory('PriceBoundPSM');

  /// Deploy DAI Peg Stability Module
  /// PSM will trade VOLT between 100 cents and 111 cents. If the Volt price exceeds 111 cents,
  /// the floor price will have to be moved lower as the oracle price is inverted.
  /// If price is outside of this band, the PSM will not allow trades
  const voltDAIPSM = await voltPSMFactory.deploy(
    voltDAIFloorPrice,
    voltDAICeilingPrice,
    {
      coreAddress: core.address,
      oracleAddress: oraclePassThrough.address, /// OPT
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: voltDAIDecimalsNormalizer,
      doInvert: true /// invert the price so that the Oracle and PSM works correctly
    },
    MINT_FEE_BASIS_POINTS,
    L2_REDEEM_FEE_BASIS_POINTS,
    reservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    L2_DAI,
    VOLT_FUSE_PCV_DEPOSIT /// intentionally set the PCV deposit as an address that does not exist on l2
    /// any calls to try to allocate surplus will fail, however the reserves threshold is too high
    /// so this call will never be be attempted in the first place
  );

  await voltDAIPSM.deployed();

  /// Deploy DAI Peg Stability Module
  /// PSM will trade VOLT between 100 cents and 111 cents. If the Volt price exceeds 111 cents,
  /// the floor price will have to be moved lower as the oracle price is inverted.
  /// If price is outside of this band, the PSM will not allow trades
  const voltUSDCPSM = await voltPSMFactory.deploy(
    voltUSDCFloorPrice,
    voltUSDCCeilingPrice,
    {
      coreAddress: core.address,
      oracleAddress: oraclePassThrough.address, /// OPT
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: voltUSDCDecimalsNormalizer,
      doInvert: true /// invert the price so that the Oracle and PSM works correctly
    },
    MINT_FEE_BASIS_POINTS,
    L2_REDEEM_FEE_BASIS_POINTS,
    reservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    L2_ARBITRUM_USDC,
    VOLT_FUSE_PCV_DEPOSIT /// intentionally set the PCV deposit as an address that does not exist on l2
    /// any calls to try to allocate surplus will fail, however the reserves threshold is too high
    /// so this call will never be be attempted in the first place
  );

  await voltUSDCPSM.deployed();

  const PCVGuardian = await ethers.getContractFactory('PCVGuardian');

  /// whitelist psm to withdraw from
  /// safe address is protocol multisig
  const pcvGuardian = await PCVGuardian.deploy(core.address, L2_ARBITRUM_PROTOCOL_MULTISIG_ADDRESS, [
    voltDAIPSM.address,
    voltUSDCPSM.address
  ]);
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

  await core.grantGovernor(L2_ARBITRUM_PROTOCOL_MULTISIG_ADDRESS); /// give multisig the governor role
  await core.grantPCVController(L2_ARBITRUM_PROTOCOL_MULTISIG_ADDRESS); /// give multisig the PCV controller role

  console.log('\n ~~~~~ Deployed Contracts Successfully ~~~~~ \n');

  console.log(`⚡Core⚡:                 ${core.address}`);
  console.log(`⚡VOLT⚡:                 ${volt}`);
  console.log(`⚡PCVGuardian⚡:          ${pcvGuardian.address}`);
  console.log(`⚡VOLT DAI PSM⚡:         ${voltDAIPSM.address}`);
  console.log(`⚡PCVGuardAdmin⚡:        ${pcvGuardAdmin.address}`);
  console.log(`⚡OraclePassThrough⚡:    ${oraclePassThrough.address}`);
  console.log(`⚡L2ScalingPriceOracle⚡: ${scalingPriceOracle.address}`);

  if (L2_DEPLOYMENT) {
    await verifyEtherscan(
      voltDAIPSM.address,
      voltUSDCPSM.address,
      core.address,
      volt,
      pcvGuardian.address,
      pcvGuardAdmin.address,
      oraclePassThrough.address,
      scalingPriceOracle.address
    );
  }

  await validateDeployment(
    core,
    pcvGuardian,
    pcvGuardAdmin,
    deployer,
    voltDAIPSM,
    voltUSDCPSM,
    oraclePassThrough,
    scalingPriceOracle
  );
}

async function verifyEtherscan(
  voltDAIPSM: string,
  voltUSDCPSM: string,
  core: string,
  volt: string,
  pcvGuardian: string,
  pcvGuardAdmin: string,
  oraclePassThrough: string,
  scalingPriceOracle: string
) {
  const daiOracleParams = {
    coreAddress: core,
    oracleAddress: oraclePassThrough,
    backupOracle: ethers.constants.AddressZero,
    decimalsNormalizer: voltDAIDecimalsNormalizer,
    doInvert: true /// invert the price so that the Oracle and PSM works correctly
  };

  const usdcOracleParams = {
    coreAddress: core,
    oracleAddress: oraclePassThrough,
    backupOracle: ethers.constants.AddressZero,
    decimalsNormalizer: voltUSDCDecimalsNormalizer,
    doInvert: true /// invert the price so that the Oracle and PSM works correctly
  };

  /// verify VOLT/DAI PSM
  await hre.run('verify:verify', {
    address: voltDAIPSM,

    constructorArguments: [
      voltDAIFloorPrice,
      voltDAICeilingPrice,
      daiOracleParams,
      MINT_FEE_BASIS_POINTS,
      L2_REDEEM_FEE_BASIS_POINTS,
      reservesThreshold,
      mintLimitPerSecond,
      voltPSMBufferCap,
      L2_DAI,
      VOLT_FUSE_PCV_DEPOSIT
    ]
  });

  /// verify VOLT/USDC PSM
  await hre.run('verify:verify', {
    address: voltUSDCPSM,

    constructorArguments: [
      voltUSDCFloorPrice,
      voltUSDCCeilingPrice,
      usdcOracleParams,
      MINT_FEE_BASIS_POINTS,
      L2_REDEEM_FEE_BASIS_POINTS,
      reservesThreshold,
      mintLimitPerSecond,
      voltPSMBufferCap,
      L2_ARBITRUM_USDC,
      VOLT_FUSE_PCV_DEPOSIT
    ]
  });

  await hre.run('verify:verify', {
    address: core,
    constructorArguments: [volt]
  });

  /// verify PCV Guardian
  await hre.run('verify:verify', {
    address: pcvGuardian,
    constructorArguments: [core, L2_ARBITRUM_PROTOCOL_MULTISIG_ADDRESS, [voltDAIPSM, voltUSDCPSM]]
  });

  /// verify Core
  await hre.run('verify:verify', {
    address: pcvGuardAdmin,
    constructorArguments: [core]
  });

  /// verify Oracle Pass Through
  await hre.run('verify:verify', {
    address: oraclePassThrough,
    constructorArguments: [scalingPriceOracle]
  });

  /// verify Scaling Price Oracle
  await hre.run('verify:verify', {
    address: scalingPriceOracle,
    constructorArguments: [
      L2_ARBITRUM_CHAINLINK_ORACLE_ADDRESS,
      L2_ARBITRUM_JOB_ID,
      L2_ARBITRUM_CHAINLINK_FEE,
      L2_ARBITRUM_CURRENT_MONTH,
      L2_ARBITRUM_PREVIOUS_MONTH,
      ACTUAL_START_TIME,
      STARTING_L2_ORACLE_PRICE
    ]
  });
}

async function validateDeployment(
  core: L2Core,
  pcvGuardian: PCVGuardian,
  pcvGuardAdmin: PCVGuardAdmin,
  deployer: SignerWithAddress,
  voltDAIPSM: PriceBoundPSM,
  voltUSDCPSM: PriceBoundPSM,
  oraclePassThrough: OraclePassThrough,
  scalingPriceOracle: ScalingPriceOracle
) {
  /// -------- Core Parameter Validation --------

  const volt = await ethers.getContractAt('Volt', await core.volt());

  /// assert that deployer doesn't have governor or any privileged roles
  expect(await core.getRoleMemberCount(await core.GOVERN_ROLE())).to.be.equal(3); // core, multisig and deployer are governor
  expect(await core.getRoleMemberCount(await core.MINTER_ROLE())).to.be.equal(0); // no minters in Core on L2
  expect(await core.getRoleMemberCount(await core.PCV_CONTROLLER_ROLE())).to.be.equal(2); // only PCV Guardian is minter

  expect(await core.isGovernor(L2_ARBITRUM_PROTOCOL_MULTISIG_ADDRESS)).to.be.true;
  expect(await core.isGovernor(deployer.address)).to.be.true;
  expect(await core.isGovernor(core.address)).to.be.true;

  expect(await core.isPCVController(deployer.address)).to.be.false;
  expect(await core.isMinter(deployer.address)).to.be.false;

  /// assert volt and core are properly linked together
  /// on l2, volt is a bridge token so it doesn't have a reference to Core and is not mintable
  expect(await core.volt()).to.be.equal(volt.address);

  expect(await core.isPCVController(L2_ARBITRUM_PROTOCOL_MULTISIG_ADDRESS)).to.be.true;
  expect(await core.isPCVController(pcvGuardian.address)).to.be.true;
  expect(await core.isGuardian(pcvGuardian.address)).to.be.true;

  expect(await core.hasRole(PCV_GUARD_ROLE, PCV_GUARD_EOA_1)).to.be.true;
  expect(await core.hasRole(PCV_GUARD_ROLE, PCV_GUARD_EOA_2)).to.be.true;

  expect(await core.hasRole(PCV_GUARD_ADMIN_ROLE, pcvGuardAdmin.address)).to.be.true;

  /// -------- PCV Guard Admin Parameter Validation --------

  expect(await pcvGuardAdmin.core()).to.be.equal(core.address);

  /// -------- PCV Guardian Parameter Validation --------

  expect(await pcvGuardian.isWhitelistAddress(voltDAIPSM.address)).to.be.true;
  expect(await pcvGuardian.isWhitelistAddress(voltUSDCPSM.address)).to.be.true;
  expect(await pcvGuardian.safeAddress()).to.be.equal(L2_ARBITRUM_PROTOCOL_MULTISIG_ADDRESS);

  /// -------- VOLT/DAI PSM Parameter Validation --------

  ///  oracle
  expect(await voltDAIPSM.doInvert()).to.be.true;
  expect(await voltDAIPSM.oracle()).to.be.equal(oraclePassThrough.address);
  expect(await voltDAIPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);
  expect(await voltDAIPSM.decimalsNormalizer()).to.be.equal(voltDAIDecimalsNormalizer);

  ///  volt
  expect(await voltDAIPSM.underlyingToken()).to.be.equal(L2_DAI);
  expect(await voltDAIPSM.volt()).to.be.equal(L2_ARBITRUM_VOLT);

  ///  psm params
  expect(await voltDAIPSM.redeemFeeBasisPoints()).to.be.equal(L2_REDEEM_FEE_BASIS_POINTS); /// 5 basis points
  expect(await voltDAIPSM.mintFeeBasisPoints()).to.be.equal(MINT_FEE_BASIS_POINTS); /// 50 basis points
  expect(await voltDAIPSM.reservesThreshold()).to.be.equal(reservesThreshold);
  expect(await voltDAIPSM.surplusTarget()).to.be.equal(VOLT_FUSE_PCV_DEPOSIT);
  expect(await voltDAIPSM.rateLimitPerSecond()).to.be.equal(mintLimitPerSecond);
  expect(await voltDAIPSM.buffer()).to.be.equal(0); /// buffer is 0 as PSM cannot mint
  expect(await voltDAIPSM.bufferCap()).to.be.equal(voltPSMBufferCap);

  ///  price bound params
  expect(await voltDAIPSM.floor()).to.be.equal(voltDAIFloorPrice);
  expect(await voltDAIPSM.ceiling()).to.be.equal(voltDAICeilingPrice);
  expect(await voltDAIPSM.isPriceValid()).to.be.true;

  ///  balance check
  expect(await voltDAIPSM.balance()).to.be.equal(0);
  expect(await voltDAIPSM.voltBalance()).to.be.equal(0);

  /// -------- VOLT/USDC PSM Parameter Validation --------

  ///  oracle
  expect(await voltUSDCPSM.doInvert()).to.be.true;
  expect(await voltUSDCPSM.oracle()).to.be.equal(oraclePassThrough.address);
  expect(await voltUSDCPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);
  expect(await voltUSDCPSM.decimalsNormalizer()).to.be.equal(voltUSDCDecimalsNormalizer);

  ///  volt
  expect(await voltUSDCPSM.underlyingToken()).to.be.equal(L2_ARBITRUM_USDC);
  expect(await voltUSDCPSM.volt()).to.be.equal(L2_ARBITRUM_VOLT);

  ///  psm params
  expect(await voltUSDCPSM.redeemFeeBasisPoints()).to.be.equal(L2_REDEEM_FEE_BASIS_POINTS); /// 5 basis points
  expect(await voltUSDCPSM.mintFeeBasisPoints()).to.be.equal(MINT_FEE_BASIS_POINTS); /// 50 basis points
  expect(await voltUSDCPSM.reservesThreshold()).to.be.equal(reservesThreshold);
  expect(await voltUSDCPSM.surplusTarget()).to.be.equal(VOLT_FUSE_PCV_DEPOSIT);
  expect(await voltUSDCPSM.rateLimitPerSecond()).to.be.equal(mintLimitPerSecond);
  expect(await voltUSDCPSM.buffer()).to.be.equal(0); /// buffer is 0 as PSM cannot mint
  expect(await voltUSDCPSM.bufferCap()).to.be.equal(voltPSMBufferCap);

  ///  price bound params
  expect(await voltUSDCPSM.floor()).to.be.equal(voltUSDCFloorPrice);
  expect(await voltUSDCPSM.ceiling()).to.be.equal(voltUSDCCeilingPrice);
  expect(await voltUSDCPSM.isPriceValid()).to.be.true;

  ///  balance check
  expect(await voltUSDCPSM.balance()).to.be.equal(0);
  expect(await voltUSDCPSM.voltBalance()).to.be.equal(0);

  /// -------- OraclePassThrough/ScalingPriceOracle Parameter Validation --------

  expect(await scalingPriceOracle.oraclePrice()).to.be.equal(STARTING_L2_ORACLE_PRICE);
  expect(await scalingPriceOracle.startTime()).to.be.equal(ACTUAL_START_TIME);

  expect(await scalingPriceOracle.currentMonth()).to.be.equal(L2_ARBITRUM_CURRENT_MONTH);
  expect(await scalingPriceOracle.previousMonth()).to.be.equal(L2_ARBITRUM_PREVIOUS_MONTH);
  expect(await scalingPriceOracle.monthlyChangeRateBasisPoints()).to.be.equal(55);

  expect(await oraclePassThrough.scalingPriceOracle()).to.be.equal(scalingPriceOracle.address);
  expect(await oraclePassThrough.owner()).to.be.equal(L2_ARBITRUM_PROTOCOL_MULTISIG_ADDRESS);
  expect(await oraclePassThrough.getCurrentOraclePrice()).to.be.equal(await scalingPriceOracle.getCurrentOraclePrice());

  console.log(`\n ~~~~~ Verified Contracts Successfully ~~~~~ \n`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

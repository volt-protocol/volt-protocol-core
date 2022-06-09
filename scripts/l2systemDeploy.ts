import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
import config from './config';
import l2config from './l2config';
import { getAllContractAddresses } from '@scripts/utils/loadContracts';
import NetworksForVerification from '@protocol/networksForVerification';
import {
  L2Core,
  OraclePassThrough,
  PCVGuardAdmin,
  PCVGuardian,
  PriceBoundPSM,
  L2ScalingPriceOracle,
  OptimisticTimelock
} from '@custom-types/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { NamedAddresses } from '@custom-types/types';

const {
  /// fees
  MINT_FEE_BASIS_POINTS,

  /// Roles
  GOVERN_ROLE,
  PCV_GUARD_ROLE,
  PCV_GUARD_ADMIN_ROLE,
  TIMELOCK_DELAY
} = config;

const {
  L2_REDEEM_FEE_BASIS_POINTS,

  /// bls cpi-u inflation data
  L2_ARBITRUM_PREVIOUS_MONTH,
  L2_ARBITRUM_CURRENT_MONTH,

  /// L2 chainlink
  STARTING_L2_ORACLE_PRICE,
  ACTUAL_START_TIME,
  L2_ARBITRUM_JOB_ID,
  L2_ARBITRUM_CHAINLINK_FEE,
  voltUSDCFloorPrice,
  voltUSDCCeilingPrice,
  voltUSDCDecimalsNormalizer,
  voltDAICeilingPrice,
  voltDAIFloorPrice,
  voltDAIDecimalsNormalizer,
  reservesThreshold,
  mintLimitPerSecond,
  voltPSMBufferCap,
  ADDRESS_ONE
} = l2config;

/// ~~~ Contract Deployment ~~~

/// 1. Core
/// 2. Scaling Price Oracle
/// 3. Oracle Pass Through
/// 4. VOLT/DAI PSM
/// 5. VOLT/USDC PSM
/// 6. PCV Guardian
/// 7. PCV Guard Admin
/// 8. Optimistic Timelock

/// Grant PSM the PCV Controller Role

async function main() {
  /// -------- System Deployment --------

  const deployer = (await ethers.getSigners())[0];

  const addresses = await getAllContractAddresses();

  const CoreFactory = await ethers.getContractFactory('L2Core');
  const core = await CoreFactory.deploy(addresses.arbitrumVolt); /// point to bridge token as Volt
  await core.deployed();

  const volt = await core.volt();

  const L2ScalingPriceOracleFactory = await ethers.getContractFactory('L2ScalingPriceOracle');
  const OraclePassThroughFactory = await ethers.getContractFactory('OraclePassThrough');

  const scalingPriceOracle = await L2ScalingPriceOracleFactory.deploy(
    addresses.arbitrumFiewsChainlinkOracle,
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
    addresses.arbitrumDai,
    ADDRESS_ONE /// intentionally set the PCV deposit as an address that does not exist on l2, address(1)
    /// any calls to try to allocate surplus will fail, however the reserves threshold is max uint
    /// so this call will never be be able to be attempted in the first place
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
    addresses.arbitrumUsdc,
    ADDRESS_ONE /// intentionally set the PCV deposit as an address that does not exist on l2, address(1)
    /// any calls to try to allocate surplus will fail, however the reserves threshold is max uint
    /// so this call will never be be able to be attempted in the first place
  );

  await voltUSDCPSM.deployed();

  const PCVGuardian = await ethers.getContractFactory('PCVGuardian');
  /// safe address is protocol multisig
  const pcvGuardian = await PCVGuardian.deploy(core.address, addresses.arbitrumProtocolMultisig, [
    voltDAIPSM.address, /// whitelist psm's to withdraw from
    voltUSDCPSM.address
  ]);
  await pcvGuardian.deployed();

  const PCVGuardAdmin = await ethers.getContractFactory('PCVGuardAdmin');
  const pcvGuardAdmin = await PCVGuardAdmin.deploy(core.address);
  await pcvGuardAdmin.deployed();

  const optimisticTimelock = await (
    await ethers.getContractFactory('OptimisticTimelock')
  ).deploy(
    core.address,
    TIMELOCK_DELAY,
    /// guards and multisig can propose and cancel
    [addresses.arbitrumProtocolMultisig, addresses.pcvGuardEOA1, addresses.pcvGuardEOA2],
    [addresses.arbitrumProtocolMultisig] /// protocol multisig is allowed to execute
  );

  await optimisticTimelock.deployed();

  console.log(`⚡Core⚡:                 ${core.address}`);
  console.log(`⚡VOLT⚡:                 ${volt}`);
  console.log(`⚡Timelock⚡:             ${optimisticTimelock.address}`);
  console.log(`⚡PCVGuardian⚡:          ${pcvGuardian.address}`);
  console.log(`⚡VOLT DAI PSM⚡:         ${voltDAIPSM.address}`);
  console.log(`⚡VOLT USDC PSM⚡:        ${voltUSDCPSM.address}`);
  console.log(`⚡PCVGuardAdmin⚡:        ${pcvGuardAdmin.address}`);
  console.log(`⚡OraclePassThrough⚡:    ${oraclePassThrough.address}`);
  console.log(`⚡L2ScalingPriceOracle⚡: ${scalingPriceOracle.address}`);

  console.log('\n ~~~~~ Deployed Contracts Successfully ~~~~~ \n');

  /// TODO: break the setup actions into a separate file / function that is run independently of the deploy script
  /// separate validation and verification on etherscan as well into distinct files or runnable commands so it isn't all at once

  /// -------- Oracle Actions --------

  /// transfer ownership to the multisig
  await oraclePassThrough.transferOwnership(addresses.arbitrumProtocolMultisig);

  /// -------- PCV Guardian Actions --------

  // Grant PCV Controller and Guardian Roles to the PCV Guardian Contract
  await core.grantPCVController(pcvGuardian.address);
  await core.grantGuardian(pcvGuardian.address);

  // Create the PCV_GUARD_ADMIN Role and Grant to the PCV Guard Admin Contract
  await core.createRole(PCV_GUARD_ADMIN_ROLE, await core.GOVERN_ROLE());
  await core.grantRole(PCV_GUARD_ADMIN_ROLE, pcvGuardAdmin.address);

  // Create the PCV Guard Role and grant the role to PCV Guards via the PCV Guard Admin contract
  await core.createRole(PCV_GUARD_ROLE, PCV_GUARD_ADMIN_ROLE);
  await pcvGuardAdmin.grantPCVGuardRole(addresses.pcvGuardEOA1);
  await pcvGuardAdmin.grantPCVGuardRole(addresses.pcvGuardEOA2);

  /// -------- Core Multisig and Timelock Actions --------

  await core.grantGovernor(addresses.arbitrumProtocolMultisig); /// give multisig the governor role
  await core.grantPCVController(addresses.arbitrumProtocolMultisig); /// give multisig the PCV controller role

  await core.grantGovernor(optimisticTimelock.address); /// give timelock the governor role
  await core.grantPCVController(optimisticTimelock.address); /// give timelock the PCV controller role

  /// -------- Deployer Revokes Governor --------

  /// deployer revokes their governor role from core
  await core.revokeGovernor(deployer.address);

  if (NetworksForVerification[hre.network.name]) {
    await verifyEtherscan(
      voltDAIPSM.address,
      voltUSDCPSM.address,
      core.address,
      volt,
      pcvGuardian.address,
      pcvGuardAdmin.address,
      optimisticTimelock.address,
      oraclePassThrough.address,
      scalingPriceOracle.address,
      addresses
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
    scalingPriceOracle,
    optimisticTimelock,
    addresses
  );
}

async function verifyEtherscan(
  voltDAIPSM: string,
  voltUSDCPSM: string,
  core: string,
  volt: string,
  pcvGuardian: string,
  pcvGuardAdmin: string,
  optimisticTimelock: string,
  oraclePassThrough: string,
  scalingPriceOracle: string,
  addresses: NamedAddresses
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
      addresses.arbitrumDai,
      ADDRESS_ONE
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
      addresses.arbitrumUsdc,
      ADDRESS_ONE
    ]
  });

  await hre.run('verify:verify', {
    address: core,
    constructorArguments: [volt]
  });

  /// verify PCV Guardian
  await hre.run('verify:verify', {
    address: pcvGuardian,
    constructorArguments: [core, addresses.arbitrumProtocolMultisig, [voltDAIPSM, voltUSDCPSM]]
  });

  /// verify PCV Guard Admin
  await hre.run('verify:verify', {
    address: pcvGuardAdmin,
    constructorArguments: [core]
  });

  /// verify Optimistic Timelock
  await hre.run('verify:verify', {
    address: optimisticTimelock,
    constructorArguments: [
      core,
      TIMELOCK_DELAY,
      [addresses.arbitrumProtocolMultisig, addresses.pcvGuardEOA1, addresses.pcvGuardEOA2],
      [addresses.arbitrumProtocolMultisig]
    ]
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
      addresses.arbitrumFiewsChainlinkOracle,
      L2_ARBITRUM_JOB_ID,
      L2_ARBITRUM_CHAINLINK_FEE,
      L2_ARBITRUM_CURRENT_MONTH,
      L2_ARBITRUM_PREVIOUS_MONTH,
      ACTUAL_START_TIME,
      STARTING_L2_ORACLE_PRICE
    ]
  });

  console.log(`\n ~~~~~ Verified Contracts On Arbiscan Successfully ~~~~~ \n`);
}

async function validateDeployment(
  core: L2Core,
  pcvGuardian: PCVGuardian,
  pcvGuardAdmin: PCVGuardAdmin,
  deployer: SignerWithAddress,
  voltDAIPSM: PriceBoundPSM,
  voltUSDCPSM: PriceBoundPSM,
  oraclePassThrough: OraclePassThrough,
  scalingPriceOracle: L2ScalingPriceOracle,
  optimisticTimelock: OptimisticTimelock,
  addresses: NamedAddresses
) {
  /// -------- Core Parameter Validation --------

  const volt = await ethers.getContractAt('Volt', await core.volt());

  expect(await core.getRoleMemberCount(await core.GOVERN_ROLE())).to.be.equal(3); // core, multisig and timelock are governor
  expect(await core.getRoleMemberCount(await core.MINTER_ROLE())).to.be.equal(0); // no minters in Core on Arbitrum, because Volt can only be minted by the Arbitrum bridge
  expect(await core.getRoleMemberCount(await core.PCV_CONTROLLER_ROLE())).to.be.equal(3); // PCV Guardian, Multisig and Timelock are PCV Controllers

  /// validate predefined roles from core are given to correct addresses
  expect(await core.isGovernor(addresses.arbitrumProtocolMultisig)).to.be.true;
  expect(await core.isGovernor(optimisticTimelock.address)).to.be.true;
  expect(await core.isGovernor(deployer.address)).to.be.false;
  expect(await core.isGovernor(core.address)).to.be.true;

  expect(await core.isPCVController(addresses.arbitrumProtocolMultisig)).to.be.true;
  expect(await core.isPCVController(pcvGuardian.address)).to.be.true;
  expect(await core.isPCVController(optimisticTimelock.address)).to.be.true;
  expect(await core.isPCVController(deployer.address)).to.be.false;

  expect(await core.isGuardian(pcvGuardian.address)).to.be.true;

  expect(await core.isMinter(deployer.address)).to.be.false;

  /// validate custom roles from core are given to correct addresses
  expect(await core.hasRole(PCV_GUARD_ROLE, addresses.pcvGuardEOA1)).to.be.true;
  expect(await core.hasRole(PCV_GUARD_ROLE, addresses.pcvGuardEOA2)).to.be.true;
  expect(await core.hasRole(PCV_GUARD_ADMIN_ROLE, pcvGuardAdmin.address)).to.be.true;

  /// validate role heirarchy for PCV Guard and PCV Guard Admin
  expect(await core.getRoleAdmin(PCV_GUARD_ADMIN_ROLE)).to.be.equal(GOVERN_ROLE);
  expect(await core.getRoleAdmin(PCV_GUARD_ROLE)).to.be.equal(PCV_GUARD_ADMIN_ROLE);

  /// assert volt and core are properly linked together
  /// on l2, volt is a bridge token so it doesn't have a reference to Core and is not mintable
  expect(await core.volt()).to.be.equal(volt.address);

  /// -------- PCV Guard Admin Parameter Validation --------

  expect(await pcvGuardAdmin.core()).to.be.equal(core.address);

  /// -------- PCV Guardian Parameter Validation --------

  expect(await pcvGuardian.core()).to.be.equal(core.address);
  expect(await pcvGuardian.isWhitelistAddress(voltDAIPSM.address)).to.be.true;
  expect(await pcvGuardian.isWhitelistAddress(voltUSDCPSM.address)).to.be.true;
  expect(await pcvGuardian.safeAddress()).to.be.equal(addresses.arbitrumProtocolMultisig);

  /// -------- Timelock Parameter Validation --------

  expect(await optimisticTimelock.core()).to.be.equal(core.address);
  expect(await optimisticTimelock.getMinDelay()).to.be.equal(TIMELOCK_DELAY);

  /// validate proposer role
  const proposerRole = await optimisticTimelock.PROPOSER_ROLE();
  expect(await optimisticTimelock.hasRole(proposerRole, addresses.pcvGuardEOA1)).to.be.true;
  expect(await optimisticTimelock.hasRole(proposerRole, addresses.pcvGuardEOA2)).to.be.true;
  expect(await optimisticTimelock.hasRole(proposerRole, addresses.arbitrumProtocolMultisig)).to.be.true;

  /// validate canceller role
  const cancellerRole = await optimisticTimelock.CANCELLER_ROLE();
  expect(await optimisticTimelock.hasRole(cancellerRole, addresses.pcvGuardEOA1)).to.be.true;
  expect(await optimisticTimelock.hasRole(cancellerRole, addresses.pcvGuardEOA2)).to.be.true;
  expect(await optimisticTimelock.hasRole(cancellerRole, addresses.arbitrumProtocolMultisig)).to.be.true;

  /// validate executor role
  const executorRole = await optimisticTimelock.EXECUTOR_ROLE();
  expect(await optimisticTimelock.hasRole(executorRole, addresses.arbitrumProtocolMultisig)).to.be.true;
  /// guards cannot execute
  expect(await optimisticTimelock.hasRole(executorRole, addresses.pcvGuardEOA1)).to.be.false;
  expect(await optimisticTimelock.hasRole(executorRole, addresses.pcvGuardEOA2)).to.be.false;

  /// -------- VOLT/DAI PSM Parameter Validation --------

  expect(await voltDAIPSM.core()).to.be.equal(core.address);

  ///  oracle
  expect(await voltDAIPSM.doInvert()).to.be.true;
  expect(await voltDAIPSM.oracle()).to.be.equal(oraclePassThrough.address);
  expect(await voltDAIPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);
  expect(await voltDAIPSM.decimalsNormalizer()).to.be.equal(voltDAIDecimalsNormalizer);

  ///  volt
  expect(await voltDAIPSM.underlyingToken()).to.be.equal(addresses.arbitrumDai);
  expect(await voltDAIPSM.volt()).to.be.equal(addresses.arbitrumVolt);

  ///  psm params
  expect(await voltDAIPSM.redeemFeeBasisPoints()).to.be.equal(L2_REDEEM_FEE_BASIS_POINTS); /// 5 basis points
  expect(await voltDAIPSM.mintFeeBasisPoints()).to.be.equal(MINT_FEE_BASIS_POINTS); /// 50 basis points
  expect(await voltDAIPSM.reservesThreshold()).to.be.equal(reservesThreshold);
  expect(await voltDAIPSM.surplusTarget()).to.be.equal(ADDRESS_ONE); /// TODO change to address 1
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

  expect(await voltUSDCPSM.core()).to.be.equal(core.address);

  ///  oracle
  expect(await voltUSDCPSM.doInvert()).to.be.true;
  expect(await voltUSDCPSM.oracle()).to.be.equal(oraclePassThrough.address);
  expect(await voltUSDCPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);
  expect(await voltUSDCPSM.decimalsNormalizer()).to.be.equal(voltUSDCDecimalsNormalizer);

  ///  volt
  expect(await voltUSDCPSM.underlyingToken()).to.be.equal(addresses.arbitrumUsdc);
  expect(await voltUSDCPSM.volt()).to.be.equal(addresses.arbitrumVolt);

  ///  psm params
  expect(await voltUSDCPSM.redeemFeeBasisPoints()).to.be.equal(L2_REDEEM_FEE_BASIS_POINTS); /// 5 basis points
  expect(await voltUSDCPSM.mintFeeBasisPoints()).to.be.equal(MINT_FEE_BASIS_POINTS); /// 50 basis points
  expect(await voltUSDCPSM.reservesThreshold()).to.be.equal(reservesThreshold);
  expect(await voltUSDCPSM.surplusTarget()).to.be.equal(ADDRESS_ONE); /// TODO change to address 1
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

  /// -------- OraclePassThrough / ScalingPriceOracle Parameter Validation --------

  expect(await scalingPriceOracle.oraclePrice()).to.be.equal(STARTING_L2_ORACLE_PRICE);
  expect(await scalingPriceOracle.startTime()).to.be.equal(ACTUAL_START_TIME);

  expect(await scalingPriceOracle.currentMonth()).to.be.equal(L2_ARBITRUM_CURRENT_MONTH);
  expect(await scalingPriceOracle.previousMonth()).to.be.equal(L2_ARBITRUM_PREVIOUS_MONTH);
  expect(await scalingPriceOracle.monthlyChangeRateBasisPoints()).to.be.equal(55); /// ensure correct monthly change rate for new scaling price oracle

  expect(await oraclePassThrough.scalingPriceOracle()).to.be.equal(scalingPriceOracle.address);
  expect(await oraclePassThrough.owner()).to.be.equal(addresses.arbitrumProtocolMultisig);
  expect(await oraclePassThrough.getCurrentOraclePrice()).to.be.equal(await scalingPriceOracle.getCurrentOraclePrice());

  console.log(`\n ~~~~~ Validated Contract Setup Successfully ~~~~~ \n`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

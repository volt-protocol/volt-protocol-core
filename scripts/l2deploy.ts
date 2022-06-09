import config from './config';
import l2config from './l2config';
import { getAllContractAddresses } from '@scripts/utils/loadContracts';
import { ethers } from 'hardhat';
import '@nomiclabs/hardhat-ethers';

const {
  /// fees
  MINT_FEE_BASIS_POINTS,
  TIMELOCK_DELAY
} = config;

const {
  L2_REDEEM_FEE_BASIS_POINTS,

  /// bls cpi-u inflation data
  L2_ARBITRUM_PREVIOUS_MONTH,
  L2_ARBITRUM_CURRENT_MONTH,

  /// Set Surplus Deposit to Address 1 to stop allocate surplus from being callable
  /// Allocate surplus can never be called because reserves threshold is max uint and therefore impossible to exceed
  /// Surplus deposit cannot be address 0 because logic in the PSM explicitly checks the 0 address, so address 1 is used instead
  ADDRESS_ONE,

  /// L2 chainlink
  STARTING_L2_ORACLE_PRICE,
  ACTUAL_START_TIME,
  L2_ARBITRUM_JOB_ID,
  L2_ARBITRUM_CHAINLINK_FEE,
  voltDAIDecimalsNormalizer,
  voltUSDCDecimalsNormalizer,
  voltDAIFloorPrice,
  voltDAICeilingPrice,
  voltUSDCFloorPrice,
  voltUSDCCeilingPrice,
  reservesThreshold,
  mintLimitPerSecond,
  voltPSMBufferCap
} = l2config;

async function deploy() {
  /// -------- System Deployment --------

  const addresses = await getAllContractAddresses();

  const CoreFactory = await ethers.getContractFactory('L2Core');
  const core = await CoreFactory.deploy(addresses.arbitrumVolt); /// point to bridge token as Volt
  await core.deployed();

  const volt = await core.volt();

  const L2ScalingPriceOracleFactory = await ethers.getContractFactory('L2ScalingPriceOracle');
  const OraclePassThroughFactory = await ethers.getContractFactory('OraclePassThrough');

  const scalingPriceOracle = await L2ScalingPriceOracleFactory.deploy(
    addresses.arbitrumFiewsChainlinkOracle,
    /// if the variables aren't reusable or needed for documentation, they shouldn't be in Config.ts
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
}

deploy()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

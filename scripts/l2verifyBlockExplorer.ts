import hre from 'hardhat';
import config from './config';
import l2config from './l2config';
import { getAllContractAddresses } from '@scripts/utils/loadContracts';
import '@nomiclabs/hardhat-ethers';

const { MINT_FEE_BASIS_POINTS, TIMELOCK_DELAY, ZERO_ADDRESS } = config;
const {
  reservesThreshold,
  mintLimitPerSecond,
  voltPSMBufferCap,
  voltDAIFloorPrice,
  voltDAICeilingPrice,
  voltDAIDecimalsNormalizer,

  voltUSDCDecimalsNormalizer,
  voltUSDCFloorPrice,
  voltUSDCCeilingPrice,

  L2_REDEEM_FEE_BASIS_POINTS,
  L2_ARBITRUM_JOB_ID,
  L2_ARBITRUM_CHAINLINK_FEE,
  L2_ARBITRUM_CURRENT_MONTH,
  L2_ARBITRUM_PREVIOUS_MONTH,
  ACTUAL_START_TIME,
  STARTING_L2_ORACLE_PRICE,
  ADDRESS_ONE
} = l2config;

async function verifyEtherscan() {
  const { arbitrumVolt, arbitrumDAIPSM, arbitrumUSDCPSM, arbitrumOraclePassThrough } = await getAllContractAddresses();
  const addresses = await getAllContractAddresses();

  const daiOracleParams = {
    coreAddress: addresses.arbitrumCore,
    oracleAddress: arbitrumOraclePassThrough,
    backupOracle: ZERO_ADDRESS,
    decimalsNormalizer: voltDAIDecimalsNormalizer,
    doInvert: true /// invert the price so that the Oracle and PSM works correctly
  };

  const usdcOracleParams = {
    coreAddress: addresses.arbitrumCore,
    oracleAddress: arbitrumOraclePassThrough,
    backupOracle: ZERO_ADDRESS,
    decimalsNormalizer: voltUSDCDecimalsNormalizer,
    doInvert: true /// invert the price so that the Oracle and PSM works correctly
  };

  /// verify VOLT/DAI PSM
  await hre.run('verify:verify', {
    address: arbitrumDAIPSM,

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
    address: arbitrumUSDCPSM,

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
    address: addresses.arbitrumCore,
    constructorArguments: [arbitrumVolt]
  });

  /// verify PCV Guardian
  await hre.run('verify:verify', {
    address: addresses.arbitrumPCVGuardian,
    constructorArguments: [
      addresses.arbitrumCore,
      addresses.arbitrumProtocolMultisig,
      [arbitrumDAIPSM, arbitrumUSDCPSM]
    ]
  });

  /// verify PCV Guard Admin
  await hre.run('verify:verify', {
    address: addresses.arbitrumPCVGuardAdmin,
    constructorArguments: [addresses.arbitrumCore]
  });

  /// verify Optimistic Timelock
  await hre.run('verify:verify', {
    address: addresses.arbitrumOptimisticTimelock,
    constructorArguments: [
      addresses.arbitrumCore,
      TIMELOCK_DELAY,
      [addresses.arbitrumProtocolMultisig, addresses.pcvGuardEOA1, addresses.pcvGuardEOA2],
      [addresses.arbitrumProtocolMultisig]
    ]
  });

  /// verify Oracle Pass Through
  await hre.run('verify:verify', {
    address: arbitrumOraclePassThrough,
    constructorArguments: [addresses.arbitrumScalingPriceOracle]
  });

  /// verify Scaling Price Oracle
  await hre.run('verify:verify', {
    address: addresses.arbitrumScalingPriceOracle,
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

verifyEtherscan()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

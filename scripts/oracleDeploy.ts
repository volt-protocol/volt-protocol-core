import { ethers } from 'hardhat';
import config from './config';

const {
  JOB_ID,
  CHAINLINK_ORACLE_ADDRESS,
  CHAINLINK_FEE,
  /// bls cpi-u inflation data
  CURRENT_MONTH_INFLATION_DATA,
  PREVIOUS_MONTH_INFLATION_DATA
} = config;

/// ~~~ Oracle Contracts ~~~

/// 1. Scaling Price Oracle
/// 2. Oracle Pass Through

async function deployOracles() {
  const ScalingPriceOracleFactory = await ethers.getContractFactory('ScalingPriceOracle');
  const OraclePassThroughFactory = await ethers.getContractFactory('OraclePassThrough');

  const scalingPriceOracle = await ScalingPriceOracleFactory.deploy(
    CHAINLINK_ORACLE_ADDRESS,
    JOB_ID,
    CHAINLINK_FEE,
    CURRENT_MONTH_INFLATION_DATA,
    PREVIOUS_MONTH_INFLATION_DATA
  );
  await scalingPriceOracle.deployed();

  const oraclePassThrough = await OraclePassThroughFactory.deploy(scalingPriceOracle.address);
  await oraclePassThrough.deployed();

  console.log('\n ~~~~~ Deployed Oracle Contracts Successfully ~~~~~ \n');
  console.log(`OraclePassThrough:        ${oraclePassThrough.address}`);
  console.log(`ScalingPriceOracle:       ${scalingPriceOracle.address}`);
}

deployOracles()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

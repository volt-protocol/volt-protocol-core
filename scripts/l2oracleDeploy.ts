import { ethers } from 'hardhat';
import config from './config';

const {
  JOB_ID,
  CHAINLINK_ORACLE_ADDRESS,
  CHAINLINK_FEE,
  /// bls cpi-u inflation data
  CURRENT_MONTH_INFLATION_DATA,
  PREVIOUS_MONTH_INFLATION_DATA,
  ACTUAL_START_TIME,
  STARTING_L2_ORACLE_PRICE,
  L2_PROTOCOL_MULTISIG_ADDRESS
} = config;

/// ~~~ Oracle Contracts ~~~

/// 1. Scaling Price Oracle

async function deployOracle() {
  const ScalingPriceOracleFactory = await ethers.getContractFactory('L2ScalingPriceOracle');

  const scalingPriceOracle = await ScalingPriceOracleFactory.deploy(
    CHAINLINK_ORACLE_ADDRESS,
    JOB_ID,
    CHAINLINK_FEE,
    CURRENT_MONTH_INFLATION_DATA,
    PREVIOUS_MONTH_INFLATION_DATA,
    ACTUAL_START_TIME,
    STARTING_L2_ORACLE_PRICE
  );
  await scalingPriceOracle.deployed();

  console.log('\n ~~~~~ Deployed Scaling Price Oracle Successfully ~~~~~ \n');
  console.log(`l2ScalingPriceOracle:       ${scalingPriceOracle.address}`);

  await scalingPriceOracle.transferOwnership(L2_PROTOCOL_MULTISIG_ADDRESS);
}

deployOracle()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

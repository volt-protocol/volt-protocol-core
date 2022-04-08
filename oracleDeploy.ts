import { ethers } from 'hardhat';

const toBN = ethers.BigNumber.from;
const currentMonthInflationData = process.env.CURRENT_MONTH_INFLATION;
const previousMonthInflationData = process.env.PREVIOUS_MONTH_INFLATION;
const chainlinkFee = toBN('10000000000000000000');
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const oracleAddress = process.env.ORACLE_ADDRESS !== undefined ? process.env.ORACLE_ADDRESS : ZERO_ADDRESS;
const jobId = ethers.utils.toUtf8Bytes('6f7fb4abcedb485ab27eb7bb39caf827');

async function deployOracles(): Promise<{
  oraclePassThrough: any;
  scalingPriceOracle: any;
}> {
  if (!currentMonthInflationData || !previousMonthInflationData) {
    throw new Error('Invalid inflation data');
  }

  const ScalingPriceOracleFactory = await ethers.getContractFactory('ScalingPriceOracle');
  const OraclePassThroughFactory = await ethers.getContractFactory('OraclePassThrough');

  const scalingPriceOracle = await ScalingPriceOracleFactory.deploy(
    oracleAddress,
    jobId,
    chainlinkFee,
    currentMonthInflationData,
    previousMonthInflationData
  );
  await scalingPriceOracle.deployed();

  const oraclePassThrough = await OraclePassThroughFactory.deploy(scalingPriceOracle.address);
  await oraclePassThrough.deployed();

  if (process.env.DEPLOY_ORACLE) {
    console.log('\n ~~~~~ Deployed Oracle Contracts Successfully ~~~~~ \n');
    console.log(`OraclePassThrough:        ${oraclePassThrough.address}`);
    console.log(`ScalingPriceOracle:       ${scalingPriceOracle.address}`);
  }

  return { oraclePassThrough, scalingPriceOracle };
}

export default deployOracles;

if (process.env.DEPLOY_ORACLE) {
  deployOracles()
    .then(() => process.exit(0))
    .catch((err) => {
      console.log(err);
      process.exit(1);
    });
}

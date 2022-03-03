import { utils } from 'ethers';
import { ethers } from 'hardhat';

async function main() {
  const data = [
    '281148',
    '278802',
    '277948',
    '276589',
    '274310',
    '273567',
    '273003',
    '271696',
    '269195',
    '267054',
    '264877',
    '263014'
  ];

  const scalingPriceOracle = process.env.SCALING_PRICE_ORACLE;
  const chainlinkOracleAddress = process.env.ORACLE;
  const jobId = utils.toUtf8Bytes(process.env.JOB_ID);
  const fee = process.env.FEE;

  const chainlinkOracleFactory = await ethers.getContractFactory('ChainlinkOracle');

  if (!data && !Array.isArray(data)) {
    throw new Error('data missing or format not an array');
  }

  const chainlinkOracle = await chainlinkOracleFactory.deploy(
    scalingPriceOracle,
    chainlinkOracleAddress,
    jobId,
    fee,
    data
  );
  await chainlinkOracle.deployTransaction.wait();

  console.log(`~~~ Successfully deployed new Chainlink Oracle ${chainlinkOracle.address} ~~~`);

  return {};
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

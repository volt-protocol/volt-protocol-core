import { ethers } from 'hardhat';

async function main() {
  const oracleAddress = process.env.ORACLE;
  const chainlinkOracle = await ethers.getContractAt('ChainlinkOracle', oracleAddress);

  if (!chainlinkOracle) {
    throw new Error('chainlinkOracle contract is not set');
  }

  const queue = [];
  for (let i = 0; i < 12; i++) {
    const elem = await chainlinkOracle.queue(i);
    queue.push(elem);
  }
  console.log(`current queue: ${queue}`);

  console.log(`\ncurrent APR From Queue: ${await chainlinkOracle.getAPRFromQueue()}`);
  console.log(`\nAddress of ScalingPriceOracle: ${await chainlinkOracle.voltOracle()}`);
  console.log(`\nAddress of ChainlinkOracle: ${await chainlinkOracle.oracle()}`);

  return {};
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

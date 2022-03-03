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

  const tx = await chainlinkOracle.requestCPIData();
  await tx.wait();

  console.log('~~~ requested CPI Data ~~~');

  return {};
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

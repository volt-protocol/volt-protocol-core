import { ethers } from 'hardhat';

const scale = ethers.constants.WeiPerEther;

async function main() {
  const receiver = process.env.RECEIVER;
  const chainlinkOracleAddress = process.env.ORACLE;

  if (!receiver) {
    throw new Error('RECEIVER environment variable is not set');
  }

  if (!chainlinkOracleAddress) {
    throw new Error('ORACLE environment variable is not set');
  }

  console.log(`receiver: ${receiver}`);
  console.log(`chainlinkOracleAddress: ${chainlinkOracleAddress}`);

  const chainlinkOracle = await ethers.getContractAt('ChainlinkOracle', chainlinkOracleAddress);

  const tx = await chainlinkOracle.withdrawLink(receiver, scale.sub(scale.div(10)));
  await tx.wait();
  console.log('~~~ link withdrawn ~~~');

  return {};
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

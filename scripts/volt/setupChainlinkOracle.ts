import { utils } from 'ethers';
import { ethers } from 'hardhat';

async function main() {
  const jobId = utils.toUtf8Bytes(process.env.JOB_ID);

  if (!jobId) {
    throw new Error('JOB_ID environment variable is not set');
  }

  const chainlinkOracle = await ethers.getContractAt('ChainlinkOracle', '0x00CE92D5DDf05b4a897BaA0D54188e448fdAb1c2');

  if (!chainlinkOracle) {
    throw new Error('chainlinkOracle contract is not set');
  }

  const tx = await chainlinkOracle.setJobID(jobId);
  await tx.wait();
  console.log('~~~ jobId set ~~~');

  const txTwo = await chainlinkOracle.setFee(ethers.constants.WeiPerEther.div(10));
  await txTwo.wait();
  console.log('~~~ Chainlink Fee Set ~~~');

  console.log('~~~ Done ~~~');

  return {};
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

import { ethers } from 'hardhat';

async function main() {
  const newOracleAddress = process.env.ORACLE_ADDRESS;
  const scalingPriceOracle = await ethers.getContractAt(
    'ScalingPriceOracle',
    '0xC06F61FFDAA8BC1FA564D9D124f364f968473a25'
  );

  if (!scalingPriceOracle) {
    throw new Error('scalingPriceOracle contract is not set');
  }

  const tx = await scalingPriceOracle.updateChainLinkCPIOracle(newOracleAddress);
  await tx.wait();

  console.log('~~~ Sent Update to ScalingPriceOracle ~~~');

  return {};
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

import hre, { ethers } from 'hardhat';
import NetworksForVerification from '@protocol/networksForVerification';

const tenMinutes = 10 * 60; /// 10 minute timelock delay

/// deploying the optimistic timelock on mainnet should look like this:
///   CORE=0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196 PROPOSERS=0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf,0xf8D0387538E8e03F3B4394dA89f221D7565a28Ee,0xd90E9181B20D8D1B5034d9f5737804Da182039F6 EXECUTORS=0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf \
///   npx hardhat run --network localhost scripts/optimisticTimelockDeploy.ts

/// Script did not hardcode core, proposers or executors because this system will be deployed
/// onto multiple networks where all of these addresses will change

async function deploy(core, proposers, executors) {
  const optimisticTimelock = await (
    await ethers.getContractFactory('OptimisticTimelock')
  ).deploy(core, tenMinutes, proposers, executors);

  await optimisticTimelock.deployed();

  console.log(`Optimistic Timelock deployed to: ${optimisticTimelock.address}`);

  return optimisticTimelock;
}

async function verifyEtherscan(optimisticTimelock: string, core: string, proposers: string[], executors: string[]) {
  await hre.run('verify:verify', {
    address: optimisticTimelock,
    constructorArguments: [core, tenMinutes, proposers, executors]
  });

  console.log('Successfully Verified Optimistic Timelock on Block Explorer'); /// can't say etherscan as it could be arbiscan
}

async function main() {
  const { EXECUTORS, PROPOSERS, CORE } = process.env;

  if (!CORE || !EXECUTORS || !PROPOSERS) {
    throw new Error('Core, Proposer(s) or Executor(s) not set in environment variables');
  }

  /// if there is an array, break addresses into their respective elements
  const proposers = PROPOSERS.split(',');
  const executors = EXECUTORS.split(',');

  const optimisticTimelock = await deploy(CORE, proposers, executors);

  if (NetworksForVerification[hre.network.name]) {
    await verifyEtherscan(optimisticTimelock.address, CORE, proposers, executors);
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

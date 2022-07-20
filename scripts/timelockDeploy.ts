import hre, { ethers } from 'hardhat';
import NetworksForVerification from '@protocol/networksForVerification';
import { TimelockController } from '@custom-types/contracts';
import { expect } from 'chai';

const oneDay = 24 * 60 * 60; /// 1 day timelock delay

/// deploying the timelock on mainnet should look like this:
///   MSIG=0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf PROPOSERS=0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf,0xA96D4a5c343d6fE141751399Fc230E9E8Ecb6fb6,0xB320e376Be6459421695F2b6B1E716AE4bc8129A,0xd90E9181B20D8D1B5034d9f5737804Da182039F6 EXECUTORS=0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf \
///   npx hardhat run --network mainnet scripts/timelockDeploy.ts

/// deploying the timelock on arbitrum should look like this:
///   MSIG=0x1A1075cef632624153176CCf19Ae0175953CF010 PROPOSERS=0x1A1075cef632624153176CCf19Ae0175953CF010,0xA96D4a5c343d6fE141751399Fc230E9E8Ecb6fb6,0xB320e376Be6459421695F2b6B1E716AE4bc8129A,0xd90E9181B20D8D1B5034d9f5737804Da182039F6 EXECUTORS=0x1A1075cef632624153176CCf19Ae0175953CF010 \
///   npx hardhat run --network arbitrumOne scripts/timelockDeploy.ts

/// Script does not hardcode msig, proposers or executors because this system will be deployed
/// onto multiple networks where all of these addresses will change

async function deploy(proposers: string[], executors: string[], multisig: string) {
  const deployer = (await ethers.getSigners())[0];
  const timelock = await (await ethers.getContractFactory('TimelockController')).deploy(oneDay, proposers, executors);
  await timelock.deployed();

  console.log(`\nTimelock deployed to: ${timelock.address}`);

  const TIMELOCK_ADMIN_ROLE = await timelock.TIMELOCK_ADMIN_ROLE();
  await timelock.grantRole(TIMELOCK_ADMIN_ROLE, multisig);
  await timelock.renounceRole(TIMELOCK_ADMIN_ROLE, deployer.address);

  console.log('\nDeployer renounced admin role, and granted admin to multisig');

  return timelock;
}

async function validate(timelock: TimelockController, proposers: string[], executors: string[], multisig: string) {
  const TIMELOCK_ADMIN_ROLE = await timelock.TIMELOCK_ADMIN_ROLE();
  const PROPOSER_ROLE = await timelock.PROPOSER_ROLE();
  const CANCELLER_ROLE = await timelock.CANCELLER_ROLE();
  const EXECUTOR_ROLE = await timelock.EXECUTOR_ROLE();
  const deployer = (await ethers.getSigners())[0];

  expect(await timelock.hasRole(TIMELOCK_ADMIN_ROLE, deployer.address)).to.be.false;
  expect(await timelock.hasRole(TIMELOCK_ADMIN_ROLE, multisig)).to.be.true;

  for (let i = 0; i < proposers.length; i++) {
    expect(await timelock.hasRole(PROPOSER_ROLE, proposers[i])).to.be.true;
    expect(await timelock.hasRole(CANCELLER_ROLE, proposers[i])).to.be.true;
  }

  for (let i = 0; i < executors.length; i++) {
    expect(await timelock.hasRole(EXECUTOR_ROLE, executors[i])).to.be.true;
  }

  console.log('\nSuccessfully Validated Deployment');
}

async function verifyEtherscan(timelock: string, proposers: string[], executors: string[]) {
  await hre.run('verify:verify', {
    address: timelock,
    constructorArguments: [oneDay, proposers, executors]
  });

  console.log('\nSuccessfully Verified Timelock on Block Explorer'); /// can't say etherscan as it could be arbiscan
}

async function main() {
  const { EXECUTORS, PROPOSERS, MSIG } = process.env;

  if (!EXECUTORS || !PROPOSERS || !MSIG) {
    throw new Error('Proposer(s), Executor(s), or Multisig not set in environment variables');
  }

  /// if there is an array, break addresses into their respective elements
  const proposers = PROPOSERS.split(',');
  const executors = EXECUTORS.split(',');

  const timelock = await deploy(proposers, executors, MSIG);

  await validate(timelock, proposers, executors, MSIG);

  if (NetworksForVerification[hre.network.name]) {
    await verifyEtherscan(timelock.address, proposers, executors);
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

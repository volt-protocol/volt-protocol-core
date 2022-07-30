import hre, { ethers } from 'hardhat';
import NetworksForVerification from '@protocol/networksForVerification';
import { TimelockController } from '@custom-types/contracts';
import { expect } from 'chai';
import { getAllContractAddresses } from './utils/loadContracts';

const oneDay = 24 * 60 * 60; /// 1 day timelock delay

async function deploy(proposers: string[], executors: string[]) {
  const deployer = (await ethers.getSigners())[0];
  const timelock = await (await ethers.getContractFactory('TimelockController')).deploy(oneDay, proposers, executors);
  await timelock.deployed();

  console.log(`\nTimelock deployed to: ${timelock.address}`);

  const TIMELOCK_ADMIN_ROLE = await timelock.TIMELOCK_ADMIN_ROLE();

  await (await timelock.renounceRole(TIMELOCK_ADMIN_ROLE, deployer.address)).wait(1);

  console.log('\nDeployer renounced admin role');

  return timelock;
}

async function validate(timelock: TimelockController, proposers: string[], executors: string[], multisig: string) {
  const TIMELOCK_ADMIN_ROLE = await timelock.TIMELOCK_ADMIN_ROLE();
  const PROPOSER_ROLE = await timelock.PROPOSER_ROLE();
  const CANCELLER_ROLE = await timelock.CANCELLER_ROLE();
  const EXECUTOR_ROLE = await timelock.EXECUTOR_ROLE();
  const deployer = (await ethers.getSigners())[0];

  expect(await timelock.hasRole(TIMELOCK_ADMIN_ROLE, timelock.address)).to.be.true;
  expect(await timelock.hasRole(TIMELOCK_ADMIN_ROLE, deployer.address)).to.be.false;
  expect(await timelock.hasRole(TIMELOCK_ADMIN_ROLE, multisig)).to.be.false;

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
  const network = hre.network.name;
  const contractAddresses = getAllContractAddresses();

  const multisig =
    network === 'mainnet' ? contractAddresses.protocolMultisig : contractAddresses.arbitrumProtocolMultisig;
  const executors = [multisig]; /// only the multisig can execute
  const proposers = [
    multisig,
    contractAddresses.pcvGuardEOA1,
    contractAddresses.pcvGuardEOA2,
    contractAddresses.pcvGuardEOA3
  ];

  const timelock = await deploy(proposers, executors);

  await validate(timelock, proposers, executors, multisig);

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

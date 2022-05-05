import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
import { utils } from 'ethers';
import { keccak256 } from 'ethers/lib/utils';
import config from './config';
import { Core } from '@custom-types/contracts';

const { CORE, MULTISIG_ADDRESS } = config;

const PCV_GUARD_ROLE = keccak256(utils.toUtf8Bytes('PCV_GUARD_ROLE'));
const GOVERN_ROLE = keccak256(utils.toUtf8Bytes('GOVERN_ROLE'));

const pcvGuardAddress = ''; //TODO fill in intial PCV Guard role address if setting at deployment

async function deploy() {
  const PCVGuardian = await ethers.getContractFactory('PCVGuardian');
  const whitelistAddresses = [];

  const pcvGuardian = await PCVGuardian.deploy(CORE, MULTISIG_ADDRESS, whitelistAddresses);
  await pcvGuardian.deployed();

  console.log('\n ~~~~~ Deployed PCV Guardian Successfully ~~~~~ \n');
  console.log(`PCV Guardian:        ${pcvGuardian.address}`);

  const core = await ethers.getContractAt('Core', CORE);

  await core.grantPCVController(pcvGuardian.address);
  await core.grantGuardian(pcvGuardian.address);

  await core.createRole(PCV_GUARD_ROLE, GOVERN_ROLE);
  await core.grantRole(PCV_GUARD_ROLE, pcvGuardAddress);

  await verifyDeployment(core, pcvGuardian.address);

  await hre.run('verify:verify', {
    address: pcvGuardian.address,
    constructorArguments: [CORE, MULTISIG_ADDRESS, whitelistAddresses]
  });

  return;
}

async function verifyDeployment(core: Core, pcvGuardian: string) {
  expect(await core.isPCVController(pcvGuardian)).to.be.true;
  expect(await core.isGuardian(pcvGuardian)).to.be.true;

  expect(await core.hasRole(PCV_GUARD_ROLE), pcvGuardAddress).to.be.true;
}

deploy()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

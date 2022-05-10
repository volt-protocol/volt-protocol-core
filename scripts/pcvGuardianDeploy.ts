import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
import config from './config';
import { Core, PCVGuardian } from '@custom-types/contracts';

const {
  CORE,
  PROTOCOL_MULTISIG_ADDRESS,
  VOLT_FUSE_PCV_DEPOSIT,
  PCV_DEPOSIT,
  PRICE_BOUND_PSM,
  PCV_GUARD_EOA_1,
  PCV_GUARD_EOA_2
} = config;

const PCV_GUARD_ROLE = ethers.utils.id('PCV_GUARD_ROLE');
const PCV_GUARD_ADMIN_ROLE = ethers.utils.id('PCV_GUARD_ADMIN_ROLE');

async function deploy() {
  const PCVGuardian = await ethers.getContractFactory('PCVGuardian');
  const whitelistAddresses = [VOLT_FUSE_PCV_DEPOSIT, PCV_DEPOSIT, PRICE_BOUND_PSM];

  const pcvGuardian = await PCVGuardian.deploy(CORE, PROTOCOL_MULTISIG_ADDRESS, whitelistAddresses);
  await pcvGuardian.deployed();

  // Deploy PCV Guardian
  console.log('\n ~~~~~ Deployed PCV Guardian Successfully ~~~~~ \n');
  console.log(`PCV Guardian:        ${pcvGuardian.address}`);

  const PCVGuardAdmin = await ethers.getContractFactory('PCVGuardAdmin');
  const pcvGuardAdmin = await PCVGuardAdmin.deploy(CORE);
  await pcvGuardAdmin.deployed();

  //Deploy PCV Guard Admin
  console.log('\n ~~~~~ Deployed PCV Guard Admin Successfully ~~~~~ \n');
  console.log(`PCV Guard Admin:        ${pcvGuardAdmin.address}`);

  const core = await ethers.getContractAt('Core', CORE);

  // Grant PCV Controller and Guardian Roles to the PCV Guardian Contract
  await core.grantPCVController(pcvGuardian.address);
  await core.grantGuardian(pcvGuardian.address);

  // Create the PCV_GUARD_ADMIN Role and Grant to the PCV Guard Admin Contract
  await core.createRole(PCV_GUARD_ADMIN_ROLE, await core.GOVERN_ROLE());
  await core.grantRole(PCV_GUARD_ADMIN_ROLE, pcvGuardAdmin.address);

  // Create the PCV Guard Role and grant the role to PCV Guards via the PCV Guard Admin contract
  await core.createRole(PCV_GUARD_ROLE, PCV_GUARD_ADMIN_ROLE);
  await pcvGuardAdmin.grantPCVGuardRole(PCV_GUARD_EOA_1);
  await pcvGuardAdmin.grantPCVGuardRole(PCV_GUARD_EOA_2);

  await validateDeployment(core, pcvGuardian);

  await hre.run('verify:verify', {
    address: pcvGuardian.address,
    constructorArguments: [CORE, PROTOCOL_MULTISIG_ADDRESS, whitelistAddresses]
  });

  return;
}

async function validateDeployment(core: Core, pcvGuardian: PCVGuardian) {
  expect(await core.isPCVController(pcvGuardian.address)).to.be.true;
  expect(await core.isGuardian(pcvGuardian.address)).to.be.true;

  expect(await core.hasRole(PCV_GUARD_ROLE, PCV_GUARD_EOA_1)).to.be.true;
  expect(await core.hasRole(PCV_GUARD_ROLE, PCV_GUARD_EOA_2)).to.be.true;

  expect(await pcvGuardian.isWhitelistAddress(VOLT_FUSE_PCV_DEPOSIT)).to.be.true;
  expect(await pcvGuardian.isWhitelistAddress(PCV_DEPOSIT)).to.be.true;
  expect(await pcvGuardian.isWhitelistAddress(PRICE_BOUND_PSM)).to.be.true;
}

deploy()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
import { utils } from 'ethers';
import { keccak256 } from 'ethers/lib/utils';
import config from './config';
import { Core, PCVGuardian } from '@custom-types/contracts';

const { CORE, PROTOCOL_MULTISIG_ADDRESS, VOLT_FUSE_PCV_DEPOSIT, PCV_DEPOSIT, PRICE_BOUND_PSM } = config;

const PCV_GUARD_ROLE = keccak256(utils.toUtf8Bytes('PCV_GUARD_ROLE'));

const pcvGuardAddress1 = '0xf8D0387538E8e03F3B4394dA89f221D7565a28Ee';
const pcvGuardAddress2 = '0xd90E9181B20D8D1B5034d9f5737804Da182039F6';

async function deploy() {
  const PCVGuardian = await ethers.getContractFactory('PCVGuardian');
  const whitelistAddresses = [VOLT_FUSE_PCV_DEPOSIT, PCV_DEPOSIT, PRICE_BOUND_PSM];

  const pcvGuardian = await PCVGuardian.deploy(CORE, PROTOCOL_MULTISIG_ADDRESS, whitelistAddresses);
  await pcvGuardian.deployed();

  console.log('\n ~~~~~ Deployed PCV Guardian Successfully ~~~~~ \n');
  console.log(`PCV Guardian:        ${pcvGuardian.address}`);

  const core = await ethers.getContractAt('Core', CORE);

  await core.grantPCVController(pcvGuardian.address);
  await core.grantGuardian(pcvGuardian.address);

  await core.createRole(PCV_GUARD_ROLE, await core.GOVERN_ROLE());
  await core.grantRole(PCV_GUARD_ROLE, pcvGuardAddress1);
  await core.grantRole(PCV_GUARD_ROLE, pcvGuardAddress2);

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

  expect(await core.hasRole(PCV_GUARD_ROLE, pcvGuardAddress1)).to.be.true;
  expect(await core.hasRole(PCV_GUARD_ROLE, pcvGuardAddress2)).to.be.true;

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

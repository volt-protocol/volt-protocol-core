import hre, { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import CBN from 'chai-bn';
import { DeployUpgradeFunc, SetupUpgradeFunc, TeardownUpgradeFunc, ValidateUpgradeFunc } from '@custom-types/types';
import { Volt } from '@custom-types/contracts';

chai.use(CBN(ethers.BigNumber));

/// deploy #1
///  Core
///    volt
///    vcon

/// deploy #2
///  Scaling Price Oracle
///  Oracle Pass Through

/// deploy #3
///  deploy fuse pool
///  FusePCVDeposit
///  PCVDripController
///  Volt/FEI PSM

const totalVconSupply = ethers.utils.parseEther('1000000000');

export const deploy: DeployUpgradeFunc = async (deployAddress, addresses, logging = false) => {
  // Deploy core
  const core = await (await ethers.getContractFactory('Core')).deploy();
  logging && console.log('core: ', core.address);

  // get VCON
  const vcon = await ethers.getContractAt('Vcon', await core.vcon());
  logging && console.log('vcon: ', vcon.address);

  // get VOLT
  const volt = await ethers.getContractAt('Volt', await core.volt());
  logging && console.log('volt: ', volt.address);

  await core.deployTransaction.wait();

  const fei = volt as unknown as Volt;
  return {
    fei,
    vcon,
    volt,
    core
  };
};

export const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  logging && console.log('No setup');
};

export const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  logging && console.log('No teardown');
};

export const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts) => {
  const { vcon, volt, core } = contracts;

  expect(await core.volt()).to.be.equal(volt.address);
  expect(await core.vcon()).to.be.equal(vcon.address);

  expect(await vcon.balanceOf(core.address)).to.be.equal(totalVconSupply);
};

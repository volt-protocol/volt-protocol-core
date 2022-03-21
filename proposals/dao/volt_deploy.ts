import hre, { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import CBN from 'chai-bn';
import { DeployUpgradeFunc, SetupUpgradeFunc, TeardownUpgradeFunc, ValidateUpgradeFunc } from '@custom-types/types';
import { Vcon, Volt } from '@custom-types/contracts';
import { Fei } from '@custom-types/contracts/Fei';
import { getContractAddress } from '@ethersproject/address';

chai.use(CBN(ethers.BigNumber));

const eth = ethers.constants.WeiPerEther;
const toBN = ethers.BigNumber.from;
const ZERO_ADDRESS = ethers.constants.AddressZero;

/// deploy #1
///  Core
///    volt
///    vcon
///  Timelock
///  VCON DAO
///  Deploy timelocks of all vested VCON
///    send all VCON to the corresponding timelocks
///  Create uniswap v2 pool with VCON and VOLT
///  Create uniswap v2 pool with VOLT and FEI

/// deploy #2
///  OSM
///  Scaling price oracle
///  Uniswap v2 TWAP oracle
///  Redemption Price Oracle
///  Fixed interest rate model

/// deploy #3
///  deploy fuse pool
///  FusePCVDeposit
///  PCVDripController
///  Volt/FEI PSM

/// timelock takes 1 day, we can adjust this later
const minTimelockDelay = 86_400;
const actualTimelockDelay = 86_400 * 2;

const totalVconSupply = ethers.utils.parseEther('1000000000');

export const deploy: DeployUpgradeFunc = async (deployAddress, addresses, logging = false) => {
  const { guardian } = addresses;

  console.log('here');
  const [deployer] = await ethers.getSigners();
  const transactionCount = await deployer.getTransactionCount();

  const futureDAOAddress = getContractAddress({
    from: deployer.address,
    nonce: transactionCount + 2
  });

  // Deploy core
  const core = await (await ethers.getContractFactory('Core')).deploy();
  logging && console.log('core: ', core.address);

  // deploy timelock
  const timelock = await (
    await ethers.getContractFactory('FeiDAOTimelock')
  ).deploy(core.address, futureDAOAddress, actualTimelockDelay, minTimelockDelay);
  logging && console.log('timelock: ', timelock.address);

  // get VCON
  const vcon = await ethers.getContractAt('Vcon', await core.vcon());
  logging && console.log('vcon: ', vcon.address);

  // get VOLT
  const volt = await ethers.getContractAt('Volt', await core.volt());
  logging && console.log('volt: ', volt.address);

  // deploy FeiDAO
  const voltDAO = await (await ethers.getContractFactory('FeiDAO')).deploy(vcon.address, timelock.address, guardian);
  logging && console.log('voltDAO: ', voltDAO.address);

  // deploy timelocked delegators

  await core.deployTransaction.wait();
  await timelock.deployTransaction.wait();
  await voltDAO.deployTransaction.wait();

  const fei = volt as unknown as Fei;
  return {
    fei,
    vcon,
    volt,
    core,
    voltDAO,
    timelock
  };
};

export const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  logging && console.log('No setup');
};

export const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  logging && console.log('No teardown');
};

export const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts) => {
  const { vcon, volt, core, voltDAO, timelock } = contracts;

  expect(await core.volt()).to.be.equal(volt.address);
  expect(await core.vcon()).to.be.equal(vcon.address);

  /// ensure that the DAO is wired up correctly
  expect(await timelock.admin()).to.be.equal(voltDAO.address);
  expect(await voltDAO.token()).to.be.equal(vcon.address);
  expect(await voltDAO.timelock()).to.be.equal(timelock.address);

  expect(await vcon.balanceOf(core.address)).to.be.equal(totalVconSupply);
};

import hre, { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import CBN from 'chai-bn';
import { DeployUpgradeFunc, SetupUpgradeFunc, TeardownUpgradeFunc, ValidateUpgradeFunc } from '@custom-types/types';
import { Vcon, Volt } from '@custom-types/contracts';
import { getContractAddress } from '@ethersproject/address';
import { keccak256 } from 'ethers/lib/utils';
import { utils } from 'ethers';

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
///  Deploy oracles
///    Scaling Price Oracle
///    Chainlink Oracle

///  Deploy timelocks of all vested VCON
///    send all VCON to the corresponding timelocks

/// TODO deploy timelocked delegators

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

const annualChangeRateBasisPoints = 1_000;
const maxDeviationThresholdBasisPoints = 5_000;
const scale = ethers.constants.WeiPerEther;

/// how often the scaling price oracle can be updated
const scalingPriceOracleUpdateTime = 100;

/// address of the chainlink oracle addres that will service our contract
const fiewKovanAddress = '0xa8EdF676c6296BdAD431D39Be198A889AF0b059b';

const jobId = utils.toUtf8Bytes('ada4e91dc26b47fa99d36d06473d567a');

const fee = scale.div(10);

const ttmInflationData = [
  '261582',
  '263014',
  '264877',
  '267054',
  '269195',
  '271696',
  '273003',
  '273567',
  '274310',
  '276589',
  '277948',
  '278802',
  '281148'
];

/// timelock takes 1 day, we can adjust this later
const minTimelockDelay = 86_400;
const actualTimelockDelay = 86_400 * 2;

const totalVconSupply = scale.mul(1_000_000_000);

/// @notice this is a TESTNET DEPLOY SCRIPT ONLY
export const deploy: DeployUpgradeFunc = async (deployAddress, addresses, logging = false) => {
  const { guardian } = addresses;

  const [deployer] = await ethers.getSigners();
  let transactionCount = await deployer.getTransactionCount();

  const futureDAOAddress = getContractAddress({
    from: deployer.address,
    nonce: transactionCount + 2
  });

  // Deploy mock core
  const core = await (await ethers.getContractFactory('MockCore')).deploy();
  logging && console.log('core: ', core.address);

  await core.deployTransaction.wait();

  // deploy timelock
  // grant all VCON tokens to deployer
  const timelock = await (
    await ethers.getContractFactory('FeiDAOTimelock')
  ).deploy(core.address, futureDAOAddress, actualTimelockDelay, minTimelockDelay);
  logging && console.log('timelock: ', timelock.address);

  await timelock.deployTransaction.wait();

  // get VCON
  const vcon = await ethers.getContractAt('Vcon', await core.vcon());
  logging && console.log('vcon: ', vcon.address);

  // get VOLT
  const volt = await ethers.getContractAt('Volt', await core.volt());
  logging && console.log('volt: ', volt.address);

  // deploy FeiDAO
  const voltDAO = await (await ethers.getContractFactory('FeiDAO')).deploy(vcon.address, timelock.address, guardian);
  logging && console.log('voltDAO: ', voltDAO.address);

  await voltDAO.deployTransaction.wait();

  /// Now deploy the chainlink and scaling price oracles...
  transactionCount = await deployer.getTransactionCount();

  const futureChainlinkOracleAddress = getContractAddress({
    from: deployer.address,
    nonce: transactionCount + 1
  });

  const scalingPriceOracleFactory = await ethers.getContractFactory('ScalingPriceOracle');
  const chainlinkOracleFactory = await ethers.getContractFactory('ChainlinkOracle');

  const scalingPriceOracle = await scalingPriceOracleFactory.deploy(
    annualChangeRateBasisPoints,
    maxDeviationThresholdBasisPoints,
    core.address,
    futureChainlinkOracleAddress
  );
  logging && console.log('scalingPriceOracle: ', scalingPriceOracle.address);

  await scalingPriceOracle.deployTransaction.wait();

  const chainlinkOracle = await chainlinkOracleFactory.deploy(
    scalingPriceOracle.address,
    fiewKovanAddress,
    jobId,
    fee,
    ttmInflationData.reverse()
  );
  logging && console.log('chainlinkOracle: ', chainlinkOracle.address);

  await chainlinkOracle.deployTransaction.wait();

  logging && console.log(' ~~~~~~~ Successfully finished deployment ~~~~~~~');

  return {
    vcon,
    volt,
    core,
    voltDAO,
    timelock,
    chainlinkOracle,
    scalingPriceOracle
  };
};

export const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  logging && console.log('No setup');
};

export const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  logging && console.log('No teardown');
};

export const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts) => {
  const { chainlinkOracle, scalingPriceOracle, volt, vcon, core, timelock, voltDAO } = contracts;
  const [deployer] = await ethers.getSigners();

  expect(await scalingPriceOracle.volt()).to.be.equal(volt.address);
  expect(await scalingPriceOracle.duration()).to.be.equal(scalingPriceOracleUpdateTime);
  expect(await scalingPriceOracle.chainlinkCPIOracle()).to.be.equal(chainlinkOracle.address);

  expect(await chainlinkOracle.voltOracle()).to.be.equal(scalingPriceOracle.address);
  expect(await chainlinkOracle.owner()).to.be.equal(deployer.address);

  /// ensure that core is wired up correctly
  expect(await core.vcon()).to.be.equal(vcon.address);
  expect(await core.volt()).to.be.equal(volt.address);

  /// ensure that the DAO is wired up correctly
  expect(await timelock.admin()).to.be.equal(voltDAO.address);
  expect(await voltDAO.token()).to.be.equal(vcon.address);
  expect(await voltDAO.timelock()).to.be.equal(timelock.address);

  expect(await vcon.balanceOf(core.address)).to.be.equal(totalVconSupply);
  console.log(' ~~~~ successfully validated oracle deployment ~~~~ ');
};

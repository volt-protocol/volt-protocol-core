import l2config from './l2config';
import { getAllContractAddresses } from '@scripts/utils/loadContracts';
import { ethers } from 'hardhat';
import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';

const {
  /// bls cpi-u inflation data
  L2_ARBITRUM_PREVIOUS_MONTH,
  L2_ARBITRUM_CURRENT_MONTH,

  /// L2 chainlink
  STARTING_L2_ORACLE_PRICE,
  ACTUAL_START_TIME,
  L2_ARBITRUM_JOB_ID,
  L2_ARBITRUM_CHAINLINK_FEE,
  L2_ARBITRUM_CHAINLINK_TOKEN
} = l2config;

async function deploy() {
  /// -------- System Deployment --------

  const addresses = await getAllContractAddresses();
  const L2ScalingPriceOracleFactory = await ethers.getContractFactory('L2ScalingPriceOracle');

  const scalingPriceOracle = await L2ScalingPriceOracleFactory.deploy(
    addresses.arbitrumFiewsChainlinkOracle,
    /// if the variables aren't reusable or needed for documentation, they shouldn't be in Config.ts
    L2_ARBITRUM_JOB_ID,
    L2_ARBITRUM_CHAINLINK_FEE,
    L2_ARBITRUM_CURRENT_MONTH,
    L2_ARBITRUM_PREVIOUS_MONTH,
    L2_ARBITRUM_CHAINLINK_TOKEN,
    ACTUAL_START_TIME,
    STARTING_L2_ORACLE_PRICE
  );
  await scalingPriceOracle.deployed();

  console.log(`⚡L2ScalingPriceOracle⚡: ${scalingPriceOracle.address}`);

  expect(await scalingPriceOracle.getChainlinkTokenAddress()).to.be.equal(L2_ARBITRUM_CHAINLINK_TOKEN);
  expect(await scalingPriceOracle.monthlyChangeRateBasisPoints()).to.be.equal(110);
  expect(await scalingPriceOracle.previousMonth()).to.be.equal(L2_ARBITRUM_PREVIOUS_MONTH);
  expect(await scalingPriceOracle.currentMonth()).to.be.equal(L2_ARBITRUM_CURRENT_MONTH);
  expect(await scalingPriceOracle.oraclePrice()).to.be.equal(STARTING_L2_ORACLE_PRICE);
  expect(await scalingPriceOracle.startTime()).to.be.equal(ACTUAL_START_TIME);
}

deploy()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

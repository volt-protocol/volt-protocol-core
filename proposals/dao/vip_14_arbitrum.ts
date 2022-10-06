import {
  DeployUpgradeFunc,
  NamedAddresses,
  SetupUpgradeFunc,
  TeardownUpgradeFunc,
  ValidateUpgradeFunc
} from '@custom-types/types';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { assertApproxEq } from '@test/helpers';

/*
Arbitrum Volt Protocol Improvement Proposal #14
Description: 
Deployment Steps
1. deploy volt system oracle with 0 monthlyChangeRateBasisPoints
Governance Steps:
1. Point Oracle Pass Through to new oracle address
2. Pause DAI PSM
3. Pause USDC PSM
*/

/// TODO update this to correct start time
let startTime;

const ZERO_MONTHLY_CHANGE_BASIS_POINTS = 0;

const vipNumber = '14';

const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  startTime = Math.floor(Date.now() / 1000).toString();

  const voltSystemOracle = await ethers.getContractAt('VoltSystemOracle', addresses.arbitrumVoltSystemOracle);

  const currentPrice = await voltSystemOracle.getCurrentOraclePrice();

  const voltSystemOracleFactory = await ethers.getContractFactory('VoltSystemOracle');

  const voltSystemOracle0Bips = await voltSystemOracleFactory.deploy(
    ZERO_MONTHLY_CHANGE_BASIS_POINTS,
    startTime,
    currentPrice
  );
  await voltSystemOracle0Bips.deployed();

  console.log(`Volt System Oracle deployed ${voltSystemOracle0Bips.address}`);

  console.log(`Successfully Deployed VIP-${vipNumber}`);
  return {
    voltSystemOracle0Bips
  };
};

const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  const {
    arbitrumUSDCPSM,
    arbitrumDAIPSM,
    arbitrumVoltSystemOracle,
    arbitrumOraclePassThrough,
    voltSystemOracle0Bips
  } = contracts;

  /// oracle pass through validation
  expect(await arbitrumOraclePassThrough.scalingPriceOracle()).to.be.equal(voltSystemOracle0Bips.address);

  /// PSMs fully paused
  expect(await arbitrumDAIPSM.mintPaused()).to.be.true;
  expect(await arbitrumUSDCPSM.mintPaused()).to.be.true;

  /// Volt System Oracle has correct price
  await assertApproxEq(
    await voltSystemOracle0Bips.getCurrentOraclePrice(),
    await arbitrumVoltSystemOracle.getCurrentOraclePrice(),
    0 /// allow 0 bips of deviation
  );

  await assertApproxEq(
    await voltSystemOracle0Bips.oraclePrice(),
    await arbitrumVoltSystemOracle.getCurrentOraclePrice(),
    0 /// allow 0 bips of deviation
  );

  await assertApproxEq(
    await voltSystemOracle0Bips.oraclePrice(),
    await arbitrumVoltSystemOracle.getCurrentOraclePrice(),
    0 /// allow 0 bips of deviation
  );

  await assertApproxEq(
    await voltSystemOracle0Bips.getCurrentOraclePrice(),
    await voltSystemOracle0Bips.oraclePrice(),
    0
  );

  console.log(`Successfully validated VIP-${vipNumber}`);
};

export { deploy, setup, teardown, validate };

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

Volt Protocol Improvement Proposal #15

Deployment Steps
1. deploy volt system oracle with 0 monthlyChangeRateBasisPoints
Governance Steps:

Governance Steps
1. Point Oracle Pass Through to new oracle address
2. Pause minting DAI PSM
3. Pause minting USDC PSM

*/

let startTime;

const ZERO_MONTHLY_CHANGE_BASIS_POINTS = 0;

const vipNumber = '15';

const currentPrice = '1062988312906423708';

const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  startTime = Math.floor(Date.now() / 1000).toString();

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
  const { usdcPriceBoundPSM, daiPriceBoundPSM, voltSystemOracle, oraclePassThrough, voltSystemOracle0Bips } = contracts;

  /// oracle pass through validation
  expect(await oraclePassThrough.scalingPriceOracle()).to.be.equal(voltSystemOracle0Bips.address);

  /// PSMs fully paused
  expect(await daiPriceBoundPSM.mintPaused()).to.be.true;
  expect(await usdcPriceBoundPSM.mintPaused()).to.be.true;

  /// Volt System Oracle has correct price
  await assertApproxEq(
    await voltSystemOracle0Bips.getCurrentOraclePrice(),
    await voltSystemOracle.getCurrentOraclePrice(),
    0 /// allow 0 bips of deviation
  );

  await assertApproxEq(
    await voltSystemOracle0Bips.oraclePrice(),
    await voltSystemOracle.getCurrentOraclePrice(),
    0 /// allow 0 bips of deviation
  );

  expect(await voltSystemOracle0Bips.getCurrentOraclePrice()).to.be.equal(await voltSystemOracle0Bips.oraclePrice());

  console.log(`Successfully validated VIP-${vipNumber}`);
};

export { deploy, setup, teardown, validate };

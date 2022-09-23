import hre, { ethers, artifacts } from 'hardhat';
import { expect } from 'chai';
import {
  DeployUpgradeFunc,
  NamedAddresses,
  SetupUpgradeFunc,
  TeardownUpgradeFunc,
  ValidateUpgradeFunc
} from '@custom-types/types';
import { VoltV2 } from '@custom-types/contracts';

/*

Timelock Proposal #9001

Description:

Steps:
  1 - Deploy New Volt Token
  2 - Deploy new DAI PSM
  3 - Deploy new USDC PSM
  4 - Deploy Token Migrator
  5 - Deploy Migrator Router
*/

const vipNumber = '13';

const voltFloorPrice = 9_000;
const voltCeilingPrice = 10_000;

const voltUsdcFloorPrice = '9000000000000000';
const voltUsdcCeilingPrice = '10000000000000000';

const reservesThreshold = ethers.constants.MaxUint256;
// these variables are currently unused as the PSM doesn't have the ability to mint
const mintLimitPerSecond = ethers.utils.parseEther('10000');
const voltPSMBufferCap = ethers.utils.parseEther('10000000');
const addressOne = '0x0000000000000000000000000000000000000001';

// Do any deployments
// This should exclusively include new contract deployments
const deploy: DeployUpgradeFunc = async (deployAddress: string, addresses: NamedAddresses, logging: boolean) => {
  const VoltV2Factory = await ethers.getContractFactory('VoltV2');

  const voltV2 = await VoltV2Factory.deploy(addresses.core);
  await voltV2.deployed();

  console.log(`Volt Toke deployed to: ${voltV2.address}`);

  const daiPriceBoundPSM = await (
    await ethers.getContractFactory('PriceBoundPSM')
  ).deploy(
    voltFloorPrice,
    voltCeilingPrice,
    {
      coreAddress: addresses.core,
      oracleAddress: addresses.voltSystemOraclePassThrough, // OPT
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: 0,
      doInvert: true, /// invert the price so that the Oracle and PSM works correctly,
      volt: voltV2.address
    },
    0, // 0 mint fee
    0, // 0 redeem fee
    reservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    addresses.dai,
    addressOne
  );

  await daiPriceBoundPSM.deployed();

  console.log(`\nDAI PriceBoundPSM deployed to: ${daiPriceBoundPSM.address}`);

  const usdcPriceBoundPSM = await (
    await ethers.getContractFactory('PriceBoundPSM')
  ).deploy(
    voltUsdcFloorPrice,
    voltUsdcCeilingPrice,
    {
      coreAddress: addresses.core,
      oracleAddress: addresses.voltSystemOraclePassThrough, // OPT
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: 12,
      doInvert: true, /// invert the price so that the Oracle and PSM works correctly,
      volt: voltV2.address
    },
    0,
    0,
    reservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    addresses.usdc,
    addressOne
  );

  console.log(`\nUSDC PriceBoundPSM deployed to: ${usdcPriceBoundPSM.address}`);

  const VoltMigrator = await ethers.getContractFactory('VoltMigrator');
  const voltMigrator = await VoltMigrator.deploy(addresses.core, voltV2.address);
  await voltMigrator.deployed();

  console.log(`\nVolt Migrator deployed to: ${voltMigrator.address}`);

  const MigratorRouter = await ethers.getContractFactory('MigratorRouter');
  const migratorRouter = await MigratorRouter.deploy(
    addresses.core,
    voltV2.address,
    daiPriceBoundPSM.address,
    usdcPriceBoundPSM.address
  );
  await migratorRouter.deployed();

  console.log(`\nMigrator Router deployed to: ${migratorRouter.address}`);

  return {
    // put returned contract objects here
  };
};

// Do any setup necessary for running the test.
// This could include setting up Hardhat to impersonate accounts,
// ensuring contracts have a specific state, etc.
const setup: SetupUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  console.log(`No actions to complete in setup for vip${vipNumber}`);
};

// Tears down any changes made in setup() that need to be
// cleaned up before doing any validation checks.
const teardown: TeardownUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  console.log(`No actions to complete in teardown for vip${vipNumber}`);
};

// Run any validations required on the vip using mocha or console logging
// IE check balances, check state of contracts, etc.
const validate: ValidateUpgradeFunc = async (addresses, oldContracts, contracts, logging) => {
  console.log(`No actions to complete in validate for vip${vipNumber}`);
};

export { deploy, setup, teardown, validate };

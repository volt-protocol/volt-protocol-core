import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
import {
  DeployUpgradeFunc,
  NamedAddresses,
  SetupUpgradeFunc,
  TeardownUpgradeFunc,
  ValidateUpgradeFunc
} from '@custom-types/types';
import config from './Config';
/*

Peg Stability Module

Description: This module is used to manage the stability of the peg.

Steps:
  0 - Deploy FEI PriceBoundPegStabilityModule
*/

const {
  CORE,
  FEI,
  ORACLE_PASS_THROUGH_ADDRESS,
  VOLT_FUSE_PCV_DEPOSIT,
  /// fees
  MINT_FEE_BASIS_POINTS,
  REDEEM_FEE_BASIS_POINTS
} = config;

const feiReservesThreshold = ethers.utils.parseEther('10000000000');
const mintLimitPerSecond = ethers.utils.parseEther('10000');
const voltPSMBufferCap = ethers.utils.parseEther('10000000');

const voltDecimalsNormalizer = 0;

const voltFloorPrice = 10_200;
const voltCeilingPrice = 11_000;

// Do any deployments
// This should exclusively include new contract deployments
const deploy = async () => {
  const voltPSMFactory = await ethers.getContractFactory('PriceBoundPSM');

  // Deploy DAI Peg Stability Module
  // PSM will trade DAI between 98 cents and 1.02 cents.
  // If price is outside of this band, the PSM will not allow trades
  const voltPSM = await voltPSMFactory.deploy(
    voltFloorPrice,
    voltCeilingPrice,
    {
      coreAddress: CORE,
      oracleAddress: ORACLE_PASS_THROUGH_ADDRESS, // OPT
      backupOracle: ethers.constants.ZERO_ADDRESS, // zero address
      decimalsNormalizer: voltDecimalsNormalizer,
      doInvert: true /// invert the price so that the Oracle works correctly
    },
    MINT_FEE_BASIS_POINTS,
    REDEEM_FEE_BASIS_POINTS,
    feiReservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    FEI,
    VOLT_FUSE_PCV_DEPOSIT
  );

  console.log('voltPSM: ', voltPSM.address);

  // Wait for psm to deploy
  await voltPSM.deployTransaction.wait();

  return {
    voltPSM
  };
};

deploy()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

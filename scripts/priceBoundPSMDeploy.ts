import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
import config from './Config';

/*
Peg Stability Module

Description: This module is used to manage the stability of the peg.

Steps:
  0 - Deploy FEI/VOLT PriceBoundPegStabilityModule
*/

const {
  CORE,
  FEI,
  VOLT,
  ORACLE_PASS_THROUGH_ADDRESS,
  VOLT_FUSE_PCV_DEPOSIT,
  PRICE_BOUND_PSM,
  /// fees
  MINT_FEE_BASIS_POINTS,
  REDEEM_FEE_BASIS_POINTS
} = config;

const feiReservesThreshold = ethers.utils.parseEther('10000000000');
const mintLimitPerSecond = ethers.utils.parseEther('10000');
const voltPSMBufferCap = ethers.utils.parseEther('10000000');

const voltDecimalsNormalizer = 0;

const voltFloorPrice = 9_000;
const voltCeilingPrice = 10_000;

// Do any deployments
// This should exclusively include new contract deployments
const deploy = async () => {
  const voltPSMFactory = await ethers.getContractFactory('PriceBoundPSM');

  // Deploy FEI Peg Stability Module
  // PSM will trade VOLT between 102 cents and 112 cents.
  // If price is outside of this band, the PSM will not allow trades
  const voltPSM = await voltPSMFactory.deploy(
    voltFloorPrice,
    voltCeilingPrice,
    {
      coreAddress: CORE,
      oracleAddress: ORACLE_PASS_THROUGH_ADDRESS, // OPT
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: voltDecimalsNormalizer,
      doInvert: true /// invert the price so that the Oracle and PSM works correctly
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

  //  ---------------------------- //
  //         Verify params         //
  //  ---------------------------- //

  //  oracle
  expect(await voltPSM.doInvert()).to.be.true;
  expect(await voltPSM.oracle()).to.be.equal(ORACLE_PASS_THROUGH_ADDRESS);
  expect(await voltPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);

  //  volt
  expect(await voltPSM.underlyingToken()).to.be.equal(FEI);
  expect(await voltPSM.volt()).to.be.equal(VOLT);

  //  psm params
  expect(await voltPSM.redeemFeeBasisPoints()).to.be.equal(REDEEM_FEE_BASIS_POINTS);
  expect(await voltPSM.mintFeeBasisPoints()).to.be.equal(MINT_FEE_BASIS_POINTS);
  expect(await voltPSM.reservesThreshold()).to.be.equal(feiReservesThreshold);
  expect(await voltPSM.surplusTarget()).to.be.equal(VOLT_FUSE_PCV_DEPOSIT);
  expect(await voltPSM.rateLimitPerSecond()).to.be.equal(mintLimitPerSecond);
  expect(await voltPSM.buffer()).to.be.equal(voltPSMBufferCap);
  expect(await voltPSM.bufferCap()).to.be.equal(voltPSMBufferCap);

  //  price bound params
  expect(await voltPSM.floor()).to.be.equal(voltFloorPrice);
  expect(await voltPSM.ceiling()).to.be.equal(voltCeilingPrice);

  //  balance check
  expect(await voltPSM.balance()).to.be.equal(0);
  expect(await voltPSM.voltBalance()).to.be.equal(0);

  return {
    voltPSM
  };
};

async function verifyDeployment() {
  const oracleParams = {
    coreAddress: CORE,
    oracleAddress: ORACLE_PASS_THROUGH_ADDRESS, // OPT
    backupOracle: ethers.constants.AddressZero,
    decimalsNormalizer: voltDecimalsNormalizer,
    doInvert: true /// invert the price so that the Oracle and PSM works correctly
  };

  await hre.run('verify:verify', {
    address: PRICE_BOUND_PSM,

    constructorArguments: [
      voltFloorPrice,
      voltCeilingPrice,
      oracleParams,
      MINT_FEE_BASIS_POINTS,
      REDEEM_FEE_BASIS_POINTS,
      feiReservesThreshold,
      mintLimitPerSecond,
      voltPSMBufferCap,
      FEI,
      VOLT_FUSE_PCV_DEPOSIT
    ]
  });
}

verifyDeployment()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

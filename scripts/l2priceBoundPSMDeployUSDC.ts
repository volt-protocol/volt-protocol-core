import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
import config from './Config';
import { getImpersonatedSigner } from '@test/helpers';

/// ---------------------------------------------------------------- ///
///                                                                  ///
///                Price Bound Peg Stability Module                  ///
///                                                                  ///
/// ---------------------------------------------------------------- ///

/// Description: This module is used to manage the stability of the peg.

/// Steps:
///  0 - Deploy USDC/VOLT PriceBoundPegStabilityModule
///  1 - Pause Redemptions on the VOLT PriceBoundPegStabilityModule
///  2 - Move VOLT into the PriceBoundPegStabilityModule to allow trades

/// This contract needs no roles in the system, just funding to allow swaps

/// ---------------------------------------------------------------- ///

const {
  L2_CORE,
  L2_DAI,
  L2_VOLT,
  PRICE_BOUND_PSM,
  VOLT_FUSE_PCV_DEPOSIT,
  MINT_FEE_BASIS_POINTS,
  REDEEM_FEE_BASIS_POINTS,
  PROTOCOL_MULTISIG_ADDRESS,
  ORACLE_PASS_THROUGH_ADDRESS
} = config;

const usdcReservesThreshold = ethers.constants.MaxUint256; /// max uint value so that we can never allocate surplus on this PSM to the pcv deposit
const mintLimitPerSecond = ethers.utils.parseEther('0'); /// 0 Volt can be minted per second max
const voltPSMBufferCap = ethers.utils.parseEther('0'); /// 0 Volt max can be minted at a time
const initialUSDCPSMVoltAmount = ethers.utils.parseEther('1941000'); /// 1.941m Volt which equals $2m at current prices

/// Oracle price gets scaled up by 1e12 to account for the differences in decimals of USDC and VOLT.
/// USDC has 6 decimals while Volt has 12, thus creating a difference that has to be normalized
const voltDAIDecimalsNormalizer = 0;
/// Need to scale up price of floor and ceiling by 1e12 to account for decimal normalizer that is factored into price
const voltFloorPrice = '9000000000000000';
const voltCeilingPrice = '10000000000000000';

/// Deploy the USDC PriceBoundPSM
const deploy = async () => {
  const voltPSMFactory = await ethers.getContractFactory('PriceBoundPSM');

  /// Deploy USDC Peg Stability Module
  /// PSM will trade VOLT between 100 cents and 111 cents. If the Volt price exceeds 111 cents,
  /// the floor price will have to be moved lower as the oracle price is inverted.
  /// If price is outside of this band, the PSM will not allow trades
  const voltPSM = await voltPSMFactory.deploy(
    voltFloorPrice,
    voltCeilingPrice,
    {
      coreAddress: L2_CORE,
      oracleAddress: ORACLE_PASS_THROUGH_ADDRESS, /// OPT
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: voltDAIDecimalsNormalizer,
      doInvert: true /// invert the price so that the Oracle and PSM works correctly
    },
    MINT_FEE_BASIS_POINTS,
    REDEEM_FEE_BASIS_POINTS,
    usdcReservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    L2_DAI,
    VOLT_FUSE_PCV_DEPOSIT
  );

  console.log('\nUSDC voltPSM: ', voltPSM.address);

  /// Wait for psm to deploy
  await voltPSM.deployTransaction.wait();

  ///  ---------------------------- ///
  ///         Verify params         ///
  ///  ---------------------------- ///

  ///  oracle
  expect(await voltPSM.doInvert()).to.be.true;
  expect(await voltPSM.oracle()).to.be.equal(ORACLE_PASS_THROUGH_ADDRESS);
  expect(await voltPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);

  ///  volt
  expect(await voltPSM.underlyingToken()).to.be.equal(L2_DAI);
  expect(await voltPSM.volt()).to.be.equal(L2_VOLT);

  ///  psm params
  expect(await voltPSM.redeemFeeBasisPoints()).to.be.equal(REDEEM_FEE_BASIS_POINTS); /// 0 basis points
  expect(await voltPSM.mintFeeBasisPoints()).to.be.equal(MINT_FEE_BASIS_POINTS); /// 30 basis points
  expect(await voltPSM.reservesThreshold()).to.be.equal(usdcReservesThreshold);
  expect(await voltPSM.surplusTarget()).to.be.equal(VOLT_FUSE_PCV_DEPOSIT);
  expect(await voltPSM.rateLimitPerSecond()).to.be.equal(mintLimitPerSecond);
  expect(await voltPSM.buffer()).to.be.equal(voltPSMBufferCap);
  expect(await voltPSM.bufferCap()).to.be.equal(voltPSMBufferCap);

  ///  price bound params
  expect(await voltPSM.floor()).to.be.equal(voltFloorPrice);
  expect(await voltPSM.ceiling()).to.be.equal(voltCeilingPrice);
  expect(await voltPSM.isPriceValid()).to.be.true;

  ///  balance check
  expect(await voltPSM.balance()).to.be.equal(0);
  expect(await voltPSM.voltBalance()).to.be.equal(0);

  if (hre.network.name === 'mainnet') {
    await verifyDeployment(voltPSM.address);
    console.log('\n ~~~ Successfully Verified PSM on Etherscan ~~~ ');
  } else {
    console.log(' ~~~ Simulating Multisig Steps ~~~ ');
    const signer = await getImpersonatedSigner(PROTOCOL_MULTISIG_ADDRESS);
    const feiPriceBoundPSM = await ethers.getContractAt('PriceBoundPSM', PRICE_BOUND_PSM);

    /// pause redemptions on this PSM
    await voltPSM.connect(signer).pauseRedeem();

    /// seed this PSM with $2m worth of Volt
    await feiPriceBoundPSM.connect(signer).withdrawERC20(VOLT, voltPSM.address, initialUSDCPSMVoltAmount);

    /// validate deployment
    expect(await voltPSM.voltBalance()).to.be.equal(initialUSDCPSMVoltAmount);
    expect(await voltPSM.redeemPaused()).to.be.true;
    console.log(' ~~~ Successfully Validated Multisig Steps ~~~ ');
  }

  return {
    voltPSM
  };
};

/// verify contract on etherscan
async function verifyDeployment(priceBoundPSMAddress: string) {
  const oracleParams = {
    coreAddress: L2_CORE,
    oracleAddress: ORACLE_PASS_THROUGH_ADDRESS, /// OPT
    backupOracle: ethers.constants.AddressZero,
    decimalsNormalizer: voltDAIDecimalsNormalizer,
    doInvert: true /// invert the price so that the Oracle and PSM works correctly
  };

  await hre.run('verify:verify', {
    address: priceBoundPSMAddress,

    constructorArguments: [
      voltFloorPrice,
      voltCeilingPrice,
      oracleParams,
      MINT_FEE_BASIS_POINTS,
      REDEEM_FEE_BASIS_POINTS,
      usdcReservesThreshold,
      mintLimitPerSecond,
      voltPSMBufferCap,
      L2_DAI,
      VOLT_FUSE_PCV_DEPOSIT
    ]
  });
}

deploy()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

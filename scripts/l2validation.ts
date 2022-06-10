import config from './config';
import l2config from './l2config';
import { getAllContracts, getAllContractAddresses } from '@scripts/utils/loadContracts';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import '@nomiclabs/hardhat-ethers';

const {
  VOLT_FUSE_PCV_DEPOSIT,
  /// fees
  MINT_FEE_BASIS_POINTS,
  TIMELOCK_DELAY
} = config;

const {
  L2_REDEEM_FEE_BASIS_POINTS,

  /// bls cpi-u inflation data
  L2_ARBITRUM_PREVIOUS_MONTH,
  L2_ARBITRUM_CURRENT_MONTH,

  /// Set Surplus Deposit to Address 1 to stop allocate surplus from being callable
  /// Allocate surplus can never be called because reserves threshold is max uint and therefore impossible to exceed
  /// Surplus deposit cannot be address 0 because logic in the PSM explicitly checks the 0 address, so address 1 is used instead
  PCV_GUARD_ROLE,
  PCV_GUARD_ADMIN_ROLE,
  GOVERN_ROLE,

  /// L2 chainlink
  STARTING_L2_ORACLE_PRICE,
  ACTUAL_START_TIME,
  L2_ARBITRUM_JOB_ID,
  L2_ARBITRUM_CHAINLINK_FEE,
  voltDAIDecimalsNormalizer,
  voltUSDCDecimalsNormalizer,
  voltDAIFloorPrice,
  voltDAICeilingPrice,
  voltUSDCFloorPrice,
  voltUSDCCeilingPrice,
  reservesThreshold,
  mintLimitPerSecond,
  voltPSMBufferCap
} = l2config;

async function validateDeployment() {
  const {
    arbitrumCore,
    arbitrumOptimisticTimelock,
    arbitrumDAIPSM,
    arbitrumUSDCPSM,
    arbitrumScalingPriceOracle,
    arbitrumOraclePassThrough,
    arbitrumPCVGuardian,
    arbitrumPCVGuardAdmin
  } = await getAllContracts();
  const addresses = await getAllContractAddresses();
  const deployer = (await ethers.getSigners())[0];

  /// -------- arbitrumCore Parameter Validation --------

  const volt = await ethers.getContractAt('Volt', await arbitrumCore.volt());

  expect(await arbitrumCore.getRoleMemberCount(await arbitrumCore.GOVERN_ROLE())).to.be.equal(3); // arbitrumCore, multisig and timelock are governor
  expect(await arbitrumCore.getRoleMemberCount(await arbitrumCore.MINTER_ROLE())).to.be.equal(0); // no minters in arbitrumCore on Arbitrum, because Volt can only be minted by the Arbitrum bridge
  expect(await arbitrumCore.getRoleMemberCount(await arbitrumCore.PCV_CONTROLLER_ROLE())).to.be.equal(3); // PCV Guardian, Multisig and Timelock are PCV Controllers

  /// validate predefined roles from arbitrumCore are given to correct addresses
  expect(await arbitrumCore.isGovernor(addresses.arbitrumProtocolMultisig)).to.be.true;
  expect(await arbitrumCore.isGovernor(arbitrumOptimisticTimelock.address)).to.be.true;
  expect(await arbitrumCore.isGovernor(deployer.address)).to.be.false;
  expect(await arbitrumCore.isGovernor(arbitrumCore.address)).to.be.true;

  expect(await arbitrumCore.isPCVController(addresses.arbitrumProtocolMultisig)).to.be.true;
  expect(await arbitrumCore.isPCVController(arbitrumPCVGuardian.address)).to.be.true;
  expect(await arbitrumCore.isPCVController(arbitrumOptimisticTimelock.address)).to.be.true;
  expect(await arbitrumCore.isPCVController(deployer.address)).to.be.false;

  expect(await arbitrumCore.isGuardian(arbitrumPCVGuardian.address)).to.be.true;

  expect(await arbitrumCore.isMinter(deployer.address)).to.be.false;

  /// validate custom roles from arbitrumCore are given to correct addresses
  expect(await arbitrumCore.hasRole(PCV_GUARD_ROLE, addresses.pcvGuardEOA1)).to.be.true;
  expect(await arbitrumCore.hasRole(PCV_GUARD_ROLE, addresses.pcvGuardEOA2)).to.be.true;
  expect(await arbitrumCore.hasRole(PCV_GUARD_ADMIN_ROLE, arbitrumPCVGuardAdmin.address)).to.be.true;

  /// validate role heirarchy for PCV Guard and PCV Guard Admin
  expect(await arbitrumCore.getRoleAdmin(PCV_GUARD_ADMIN_ROLE)).to.be.equal(GOVERN_ROLE);
  expect(await arbitrumCore.getRoleAdmin(PCV_GUARD_ROLE)).to.be.equal(PCV_GUARD_ADMIN_ROLE);

  /// assert volt and arbitrumCore are properly linked together
  /// on l2, volt is a bridge token so it doesn't have a reference to arbitrumCore and is not mintable
  expect(await arbitrumCore.volt()).to.be.equal(volt.address);

  /// -------- PCV Guard Admin Parameter Validation --------

  expect(await arbitrumPCVGuardAdmin.core()).to.be.equal(arbitrumCore.address);

  /// -------- PCV Guardian Parameter Validation --------

  expect(await arbitrumPCVGuardian.core()).to.be.equal(arbitrumCore.address);
  expect(await arbitrumPCVGuardian.isWhitelistAddress(arbitrumDAIPSM.address)).to.be.true;
  expect(await arbitrumPCVGuardian.isWhitelistAddress(arbitrumUSDCPSM.address)).to.be.true;
  expect(await arbitrumPCVGuardian.safeAddress()).to.be.equal(addresses.arbitrumProtocolMultisig);

  /// -------- Timelock Parameter Validation --------

  expect(await arbitrumOptimisticTimelock.core()).to.be.equal(arbitrumCore.address);
  expect(await arbitrumOptimisticTimelock.getMinDelay()).to.be.equal(TIMELOCK_DELAY);

  /// validate proposer role
  const proposerRole = await arbitrumOptimisticTimelock.PROPOSER_ROLE();
  expect(await arbitrumOptimisticTimelock.hasRole(proposerRole, addresses.pcvGuardEOA1)).to.be.true;
  expect(await arbitrumOptimisticTimelock.hasRole(proposerRole, addresses.pcvGuardEOA2)).to.be.true;
  expect(await arbitrumOptimisticTimelock.hasRole(proposerRole, addresses.arbitrumProtocolMultisig)).to.be.true;

  /// validate canceller role
  const cancellerRole = await arbitrumOptimisticTimelock.CANCELLER_ROLE();
  expect(await arbitrumOptimisticTimelock.hasRole(cancellerRole, addresses.pcvGuardEOA1)).to.be.true;
  expect(await arbitrumOptimisticTimelock.hasRole(cancellerRole, addresses.pcvGuardEOA2)).to.be.true;
  expect(await arbitrumOptimisticTimelock.hasRole(cancellerRole, addresses.arbitrumProtocolMultisig)).to.be.true;

  /// validate executor role
  const executorRole = await arbitrumOptimisticTimelock.EXECUTOR_ROLE();
  expect(await arbitrumOptimisticTimelock.hasRole(executorRole, addresses.arbitrumProtocolMultisig)).to.be.true;
  /// guards cannot execute
  expect(await arbitrumOptimisticTimelock.hasRole(executorRole, addresses.pcvGuardEOA1)).to.be.false;
  expect(await arbitrumOptimisticTimelock.hasRole(executorRole, addresses.pcvGuardEOA2)).to.be.false;

  /// -------- VOLT/DAI PSM Parameter Validation --------

  expect(await arbitrumDAIPSM.core()).to.be.equal(arbitrumCore.address);

  ///  oracle
  expect(await arbitrumDAIPSM.doInvert()).to.be.true;
  expect(await arbitrumDAIPSM.oracle()).to.be.equal(arbitrumOraclePassThrough.address);
  expect(await arbitrumDAIPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);
  expect(await arbitrumDAIPSM.decimalsNormalizer()).to.be.equal(voltDAIDecimalsNormalizer);

  ///  volt
  expect(await arbitrumDAIPSM.underlyingToken()).to.be.equal(addresses.arbitrumDai);
  expect(await arbitrumDAIPSM.volt()).to.be.equal(addresses.arbitrumVolt);

  ///  psm params
  expect(await arbitrumDAIPSM.redeemFeeBasisPoints()).to.be.equal(L2_REDEEM_FEE_BASIS_POINTS); /// 5 basis points
  expect(await arbitrumDAIPSM.mintFeeBasisPoints()).to.be.equal(MINT_FEE_BASIS_POINTS); /// 50 basis points
  expect(await arbitrumDAIPSM.reservesThreshold()).to.be.equal(reservesThreshold);
  expect(await arbitrumDAIPSM.surplusTarget()).to.be.equal(VOLT_FUSE_PCV_DEPOSIT); /// TODO change to address 1
  expect(await arbitrumDAIPSM.rateLimitPerSecond()).to.be.equal(mintLimitPerSecond);
  expect(await arbitrumDAIPSM.buffer()).to.be.equal(0); /// buffer is 0 as PSM cannot mint
  expect(await arbitrumDAIPSM.bufferCap()).to.be.equal(voltPSMBufferCap);

  ///  price bound params
  expect(await arbitrumDAIPSM.floor()).to.be.equal(voltDAIFloorPrice);
  expect(await arbitrumDAIPSM.ceiling()).to.be.equal(voltDAICeilingPrice);
  expect(await arbitrumDAIPSM.isPriceValid()).to.be.true;

  ///  balance check
  expect(await arbitrumDAIPSM.balance()).to.be.equal(0);
  expect(await arbitrumDAIPSM.voltBalance()).to.be.equal(0);

  /// -------- VOLT/USDC PSM Parameter Validation --------

  expect(await arbitrumUSDCPSM.core()).to.be.equal(arbitrumCore.address);

  ///  oracle
  expect(await arbitrumUSDCPSM.doInvert()).to.be.true;
  expect(await arbitrumUSDCPSM.oracle()).to.be.equal(arbitrumOraclePassThrough.address);
  expect(await arbitrumUSDCPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);
  expect(await arbitrumUSDCPSM.decimalsNormalizer()).to.be.equal(voltUSDCDecimalsNormalizer);

  ///  volt
  expect(await arbitrumUSDCPSM.underlyingToken()).to.be.equal(addresses.arbitrumUsdc);
  expect(await arbitrumUSDCPSM.volt()).to.be.equal(addresses.arbitrumVolt);

  ///  psm params
  expect(await arbitrumUSDCPSM.redeemFeeBasisPoints()).to.be.equal(L2_REDEEM_FEE_BASIS_POINTS); /// 5 basis points
  expect(await arbitrumUSDCPSM.mintFeeBasisPoints()).to.be.equal(MINT_FEE_BASIS_POINTS); /// 50 basis points
  expect(await arbitrumUSDCPSM.reservesThreshold()).to.be.equal(reservesThreshold);
  expect(await arbitrumUSDCPSM.surplusTarget()).to.be.equal(VOLT_FUSE_PCV_DEPOSIT); /// TODO change to address 1
  expect(await arbitrumUSDCPSM.rateLimitPerSecond()).to.be.equal(mintLimitPerSecond);
  expect(await arbitrumUSDCPSM.buffer()).to.be.equal(0); /// buffer is 0 as PSM cannot mint
  expect(await arbitrumUSDCPSM.bufferCap()).to.be.equal(voltPSMBufferCap);

  ///  price bound params
  expect(await arbitrumUSDCPSM.floor()).to.be.equal(voltUSDCFloorPrice);
  expect(await arbitrumUSDCPSM.ceiling()).to.be.equal(voltUSDCCeilingPrice);
  expect(await arbitrumUSDCPSM.isPriceValid()).to.be.true;

  ///  balance check
  expect(await arbitrumUSDCPSM.balance()).to.be.equal(0);
  expect(await arbitrumUSDCPSM.voltBalance()).to.be.equal(0);

  /// -------- arbitrumOraclePassThrough / arbitrumScalingPriceOracle Parameter Validation --------

  expect(await arbitrumScalingPriceOracle.oraclePrice()).to.be.equal(STARTING_L2_ORACLE_PRICE);
  expect(await arbitrumScalingPriceOracle.startTime()).to.be.equal(ACTUAL_START_TIME);

  expect(await arbitrumScalingPriceOracle.currentMonth()).to.be.equal(L2_ARBITRUM_CURRENT_MONTH);
  expect(await arbitrumScalingPriceOracle.previousMonth()).to.be.equal(L2_ARBITRUM_PREVIOUS_MONTH);
  expect(await arbitrumScalingPriceOracle.monthlyChangeRateBasisPoints()).to.be.equal(55); /// ensure correct monthly change rate for new scaling price oracle

  expect(await arbitrumOraclePassThrough.scalingPriceOracle()).to.be.equal(arbitrumScalingPriceOracle.address);
  expect(await arbitrumOraclePassThrough.owner()).to.be.equal(addresses.arbitrumProtocolMultisig);
  expect(await arbitrumOraclePassThrough.getCurrentOraclePrice()).to.be.equal(
    await arbitrumScalingPriceOracle.getCurrentOraclePrice()
  );

  expect(hexToASCII((await arbitrumScalingPriceOracle.jobId()).substring(2))).to.be.equal(
    ethers.utils.toUtf8String(L2_ARBITRUM_JOB_ID)
  );
  expect(await arbitrumScalingPriceOracle.fee()).to.be.equal(L2_ARBITRUM_CHAINLINK_FEE);

  console.log(`\n ~~~~~ Validated Contract Setup Successfully ~~~~~ \n`);
}

/// credit: geeks for geeks https://www.geeksforgeeks.org/convert-hexadecimal-value-string-ascii-value-string/
function hexToASCII(hex) {
  // initialize the ASCII code string as empty.
  let ascii = '';

  for (let i = 0; i < hex.length; i += 2) {
    // extract two characters from hex string
    const part = hex.substring(i, i + 2);

    // change it into base 16 and
    // typecast as the character
    const ch = String.fromCharCode(parseInt(part, 16));

    // add this char to final ASCII string
    ascii = ascii + ch;
  }
  return ascii;
}

validateDeployment()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

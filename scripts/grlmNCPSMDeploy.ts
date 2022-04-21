import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
import config from './config';
import { Core, NonCustodialPSM, GlobalRateLimitedMinter } from '@custom-types/contracts';

const {
  CORE,
  GLOBAL_RATE_LIMITED_MINTER,
  PCV_DEPOSIT,
  NON_CUSTODIAL_PSM,
  NEW_DEPLOYER_MINT_AMOUNT,
  /// addresses
  FEI,
  ZERO_ADDRESS,
  ORACLE_PASS_THROUGH_ADDRESS,
  /// fees
  MINT_FEE_BASIS_POINTS,
  REDEEM_FEE_BASIS_POINTS,
  /// grlm/psm constants
  MAX_BUFFER_CAP,
  RATE_LIMIT_PER_SECOND,
  MAX_RATE_LIMIT_PER_SECOND,
  GLOBAL_MAX_RATE_LIMIT_PER_SECOND,
  MAX_BUFFER_CAP_MULTI_RATE_LIMITED,
  PER_ADDRESS_MAX_RATE_LIMIT_PER_SECOND
} = config;

/// 1. GlobalRateLimitedMinter
/// 2. Non Custodial PSM

/// Grant PSM the PCV Controller Role
/// Grant GlobalRateLimitedMinter the Minter Role
/// Give the PSM a rate limited buffer stream in the GlobalRateLimitedMinter

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const core = await ethers.getContractAt('Core', CORE);

  const GlobalRateLimitedMinterFactory = await ethers.getContractFactory('GlobalRateLimitedMinter');
  const globalRateLimitedMinter = await GlobalRateLimitedMinterFactory.deploy(
    CORE,
    GLOBAL_MAX_RATE_LIMIT_PER_SECOND,
    PER_ADDRESS_MAX_RATE_LIMIT_PER_SECOND,
    MAX_RATE_LIMIT_PER_SECOND,
    MAX_BUFFER_CAP,
    MAX_BUFFER_CAP_MULTI_RATE_LIMITED
  );
  await globalRateLimitedMinter.deployed();

  const oracleParams = {
    coreAddress: core.address,
    oracleAddress: ORACLE_PASS_THROUGH_ADDRESS,
    backupOracle: ZERO_ADDRESS,
    decimalsNormalizer: 0
  };

  const rateLimitedParams = {
    maxRateLimitPerSecond: MAX_RATE_LIMIT_PER_SECOND,
    rateLimitPerSecond: RATE_LIMIT_PER_SECOND,
    bufferCap: MAX_BUFFER_CAP
  };

  const psmParams = {
    mintFeeBasisPoints: MINT_FEE_BASIS_POINTS,
    redeemFeeBasisPoints: REDEEM_FEE_BASIS_POINTS,
    underlyingToken: FEI,
    pcvDeposit: PCV_DEPOSIT,
    rateLimitedMinter: globalRateLimitedMinter.address
  };

  const NonCustodialPSMFactory = await ethers.getContractFactory('NonCustodialPSM');
  const nonCustodialPSM = await NonCustodialPSMFactory.deploy(oracleParams, rateLimitedParams, psmParams);

  await nonCustodialPSM.pause();

  await core.revokeMinter(GLOBAL_RATE_LIMITED_MINTER);
  await core.revokePCVController(NON_CUSTODIAL_PSM);

  await core.grantPCVController(nonCustodialPSM.address);
  await core.grantMinter(globalRateLimitedMinter.address);

  /// do not replenish minting abilities for PSM or deployer
  // set psm to 0 mint amt by revoking minting capabilities from the GRLM

  // give deployer another 20m volt to mint
  await globalRateLimitedMinter.addAddress(deployer.address, 0, NEW_DEPLOYER_MINT_AMOUNT);
  /// transfer all 10m volt to the nc psm to save on gas fees when initial users come into the system
  await globalRateLimitedMinter.mintVolt(nonCustodialPSM.address, MAX_BUFFER_CAP);

  console.log('\n ~~~~~ Deployed Contracts Successfully ~~~~~ \n');

  console.log(`GlobalRateLimitedMinter:  ${globalRateLimitedMinter.address}`);
  console.log(`Non Custodial PSM:        ${nonCustodialPSM.address}`);

  await verifyDeployment(
    GLOBAL_RATE_LIMITED_MINTER,
    NON_CUSTODIAL_PSM,
    deployer.address,
    globalRateLimitedMinter,
    nonCustodialPSM,
    core
  );
  await verifyEtherscan(nonCustodialPSM.address, globalRateLimitedMinter.address);
}

async function verifyDeployment(
  oldGRLMAddress: string,
  oldPSMAddress: string,
  deployerAddress: string,
  newGRLM: GlobalRateLimitedMinter,
  newPSM: NonCustodialPSM,
  core: Core
) {
  const volt = await ethers.getContractAt('Volt', await core.volt());

  expect(await volt.balanceOf(newPSM.address)).to.be.equal(MAX_BUFFER_CAP);
  expect(await volt.balanceOf(oldPSMAddress)).to.be.equal(0);

  expect(await core.isMinter(oldGRLMAddress)).to.be.false;
  expect(await core.isPCVController(oldPSMAddress)).to.be.false;

  expect(await core.isMinter(newGRLM.address)).to.be.true;
  expect(await core.isPCVController(newPSM.address)).to.be.true;

  expect(await newPSM.paused()).to.be.true;

  expect(await newGRLM.individualBuffer(deployerAddress)).to.be.equal(MAX_BUFFER_CAP);

  expect(await core.getRoleMemberCount(await core.GOVERN_ROLE())).to.be.equal(2); // core and deployer are governor
  expect(await core.getRoleMemberCount(await core.MINTER_ROLE())).to.be.equal(1); // only GRLM is minter
  expect(await core.getRoleMemberCount(await core.PCV_CONTROLLER_ROLE())).to.be.equal(1); // only GRLM is minter
}

async function verifyEtherscan(nonCustodialPSM: string, globalRateLimitedMinter: string) {
  const oracleParams = {
    coreAddress: CORE,
    oracleAddress: ORACLE_PASS_THROUGH_ADDRESS,
    backupOracle: ZERO_ADDRESS,
    decimalsNormalizer: 0
  };

  const rateLimitedParams = {
    maxRateLimitPerSecond: MAX_RATE_LIMIT_PER_SECOND,
    rateLimitPerSecond: RATE_LIMIT_PER_SECOND,
    bufferCap: MAX_BUFFER_CAP
  };

  const psmParams = {
    mintFeeBasisPoints: MINT_FEE_BASIS_POINTS,
    redeemFeeBasisPoints: REDEEM_FEE_BASIS_POINTS,
    underlyingToken: FEI,
    pcvDeposit: PCV_DEPOSIT,
    rateLimitedMinter: globalRateLimitedMinter
  };

  await hre.run('verify:verify', {
    address: nonCustodialPSM,

    constructorArguments: [oracleParams, rateLimitedParams, psmParams]
  });

  await hre.run('verify:verify', {
    address: globalRateLimitedMinter,

    constructorArguments: [
      CORE,
      GLOBAL_MAX_RATE_LIMIT_PER_SECOND,
      PER_ADDRESS_MAX_RATE_LIMIT_PER_SECOND,
      MAX_RATE_LIMIT_PER_SECOND,
      MAX_BUFFER_CAP,
      MAX_BUFFER_CAP_MULTI_RATE_LIMITED
    ]
  });
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

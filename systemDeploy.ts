import { ethers } from 'hardhat';
import deployOracles from './oracleDeploy';

const toBN = ethers.BigNumber.from;

const mintFeeBasisPoints = 200;
const redeemFeeBasisPoints = 0;

const maxBufferCap = '10000000000000000000000000';
const rateLimitPerSecond = '10000000000000000000000';
const maxRateLimitPerSecond = '100000000000000000000000';

const globalMaxRateLimitPerSecond = '100000000000000000000000';
const perAddressMaxRateLimitPerSecond = '15000000000000000000000';

const maxBufferCapMultiRateLimited = toBN('100000000000000000000000000');

const FEI = '0x956F47F50A910163D8BF957Cf5846D573E7f87CA';
const POOL_8_FEI = '0xd8553552f8868C1Ef160eEdf031cF0BCf9686945';
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

const psmBufferCap = '10000000000000000000000000';

/// Order of deployment operations

/// 1. Scaling Price Oracle
/// 2. Oracle Pass Through
/// 3. Core
/// 4. GlobalRateLimitedMinter
/// 5. MockERC20 /// On mainnet deploy this will default to FEI and will not need a deployment
/// 6. PCVDeposit
/// 7. Non Custodial PSM

/// Grant PSM the PCV Controller Role
/// Grant GlobalRateLimitedMinter the Minter Role
/// Give the PSM a rate limited buffer stream in the GlobalRateLimitedMinter

const mainnetDeployment = process.env.MAINNET_DEPLOYMENT;

async function main() {
  const deployer = (await ethers.getSigners())[0];

  const { scalingPriceOracle, oraclePassThrough } = await deployOracles();

  const CoreFactory = await ethers.getContractFactory('Core');
  const core = await CoreFactory.deploy();
  await core.deployed();
  await core.init();

  const volt = await core.volt();

  const GlobalRateLimitedMinterFactory = await ethers.getContractFactory('GlobalRateLimitedMinter');
  const globalRateLimitedMinter = await GlobalRateLimitedMinterFactory.deploy(
    core.address,
    globalMaxRateLimitPerSecond,
    perAddressMaxRateLimitPerSecond,
    maxRateLimitPerSecond,
    maxBufferCap,
    maxBufferCapMultiRateLimited
  );
  await globalRateLimitedMinter.deployed();

  let underlyingToken;
  let pcvDeposit;
  if (mainnetDeployment) {
    console.log('Mainnet Deployment');
    const compoundPCVDepositFactory = await ethers.getContractFactory('ERC20CompoundPCVDeposit');
    pcvDeposit = await compoundPCVDepositFactory.deploy(core.address, POOL_8_FEI);
    underlyingToken = await ethers.getContractAt('ERC20', FEI);
  } else {
    const MockERC20Factory = await ethers.getContractFactory('MockERC20');
    underlyingToken = await MockERC20Factory.deploy();
    await underlyingToken.deployed();

    const MockPCVDepositV2 = await ethers.getContractFactory('MockPCVDepositV2');

    pcvDeposit = await MockPCVDepositV2.deploy(core.address, underlyingToken.address, 0, 0);
    await pcvDeposit.deployed();
  }

  const NonCustodialPSMFactory = await ethers.getContractFactory('NonCustodialPSM');

  const oracleParams = {
    coreAddress: core.address,
    oracleAddress: oraclePassThrough.address,
    backupOracle: ZERO_ADDRESS,
    decimalsNormalizer: 0
  };

  const rateLimitedParams = {
    maxRateLimitPerSecond: maxRateLimitPerSecond,
    rateLimitPerSecond: rateLimitPerSecond,
    bufferCap: maxBufferCap
  };

  const psmParams = {
    mintFeeBasisPoints,
    redeemFeeBasisPoints,
    underlyingToken: underlyingToken.address,
    pcvDeposit: pcvDeposit.address,
    rateLimitedMinter: globalRateLimitedMinter.address
  };

  const nonCustodialPSM = await NonCustodialPSMFactory.deploy(oracleParams, rateLimitedParams, psmParams);
  await nonCustodialPSM.deployed();

  await core.grantPCVController(nonCustodialPSM.address);
  await core.grantMinter(globalRateLimitedMinter.address);
  /// do not replenish minting abilities for PSM or deployer
  await globalRateLimitedMinter.addAddress(nonCustodialPSM.address, 0, psmBufferCap);
  await globalRateLimitedMinter.addAddress(deployer.address, 0, toBN(psmBufferCap).mul(12).div(10));

  console.log('\n ~~~~~ Deployed Contracts Successfully ~~~~~ \n');

  console.log(`Core:                     ${core.address}`);
  console.log(`⚡VOLT⚡:                 ${volt}`);
  console.log(`OraclePassThrough:        ${oraclePassThrough.address}`);
  console.log(`ScalingPriceOracle:       ${scalingPriceOracle.address}`);
  console.log(`GlobalRateLimitedMinter:  ${globalRateLimitedMinter.address}`);
  console.log(`UnderlyingToken:          ${underlyingToken.address}`);
  console.log(`MockPCVDepositV2:         ${pcvDeposit.address}`);
  console.log(`Non Custodial PSM:        ${nonCustodialPSM.address}`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

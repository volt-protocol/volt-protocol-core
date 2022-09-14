import { ethers } from 'ethers';

const config = {
  /// Volt System Oracle Params
  STARTING_ORACLE_PRICE: '1055473122573580018',
  ORACLE_PERIOD_START_TIME: '1663268400', /// September 13th, 12pm pst start time
  MONTHLY_CHANGE_RATE_BASIS_POINTS: 12, /// Compound Trailing 30 Day Average yield is ~1.5% per year, in bips that is 150 bips

  /// Mainnet
  MAINNET_DEPLOYMENT: true,
  CHAINLINK_FEE: ethers.utils.parseEther('10'),
  CHAINLINK_ORACLE_ADDRESS: '0x049bd8c3adc3fe7d3fc2a44541d955a537c2a484',
  ORACLE_PASS_THROUGH_ADDRESS: '0x84dc71500D504163A87756dB6368CC8bB654592f',
  SCALING_PRICE_ORACLE_ADDRESS: '0x79412660E95F94a4D2d02a050CEA776200939917',
  CORE: '0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196',
  VOLT: '0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18',
  VOLT_FUSE_PCV_DEPOSIT: '0xFeBDf448C8484834bb399d930d7E1bdC773E23bA',
  GLOBAL_RATE_LIMITED_MINTER: '0x87945f59E008aDc9ed6210a8e061f009d6ace718',
  PCV_DEPOSIT: '0x4188fbD7aDC72853E3275F1c3503E170994888D7',
  NON_CUSTODIAL_PSM: '0x18f251FC3CE0Cb690F13f62213aba343657d0E72',
  PRICE_BOUND_PSM: '0x985f9C331a9E4447C782B98D6693F5c7dF8e560e',
  PRICE_BOUND_PSM_USDC: '0x0b9A7EA2FCA868C93640Dd77cF44df335095F501',
  MULTISIG_ADDRESS: '0x016177eDbB6809338Fda77b493cA01EA6D7Fc0D4',
  PROTOCOL_MULTISIG_ADDRESS: '0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf',
  FEI_DAI_PSM: '0x2A188F9EB761F70ECEa083bA6c2A40145078dfc2',
  FEI_DAO_TIMELOCK: '0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c',
  FEI_VOLT_OTC_SWAP: '0xeF152E462B59940616E667E801762dA9F2AF97b9',
  JOB_ID: ethers.utils.toUtf8Bytes('6f7fb4abcedb485ab27eb7bb39caf827'),
  CURRENT_MONTH_INFLATION_DATA: '287504', // March 2022 Inflation Data
  PREVIOUS_MONTH_INFLATION_DATA: '283716', // February 2022 Inflation Data
  MINT_FEE_BASIS_POINTS: 50, // Fee set at 50 basis points
  REDEEM_FEE_BASIS_POINTS: 0,
  DEPLOYER_VOLT_AMOUNT: ethers.utils.parseEther('40000000'), // 40m
  MAX_BUFFER_CAP: ethers.utils.parseEther('10000000'), // 10m
  VOLT_SWAP_AMOUNT: ethers.utils.parseEther('10000000'), // 10m
  NEW_DEPLOYER_MINT_AMOUNT: ethers.utils.parseEther('20000000'), // 20m
  MAX_BUFFER_CAP_MULTI_RATE_LIMITED: ethers.utils.parseEther('100000000'), // 100m
  RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('10000'), // 10k VOLT/s
  MAX_RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('100000'), // 100k VOLT/s
  GLOBAL_MAX_RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('100000'), // 100k VOLT/s
  PER_ADDRESS_MAX_RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('15000'), // 15k VOLT/s
  PSM_BUFFER_CAP: ethers.utils.parseEther('10000000'), // 10m VOLT
  FEI: '0x956F47F50A910163D8BF957Cf5846D573E7f87CA',
  DAI: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
  USDC: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
  POOL_8_FEI: '0xd8553552f8868C1Ef160eEdf031cF0BCf9686945',
  ZERO_ADDRESS: ethers.constants.AddressZero,
  PCV_GUARDIAN: '0x2c2b362e6ae0F080F39b90Cb5657E5550090D6C3',
  PCV_GUARD_ADMIN: '0x868F58Ae8F6B2Dc31D9ADc97a8A09B16f05E9cd7',
  PCV_GUARD_EOA_1: '0xf8D0387538E8e03F3B4394dA89f221D7565a28Ee',
  PCV_GUARD_EOA_2: '0xd90E9181B20D8D1B5034d9f5737804Da182039F6',

  /// Roles
  PCV_GUARD_ROLE: ethers.utils.id('PCV_GUARD_ROLE'),
  PCV_GUARD_ADMIN_ROLE: ethers.utils.id('PCV_GUARD_ADMIN_ROLE'),
  GOVERN_ROLE: ethers.utils.id('GOVERN_ROLE'),

  TIMELOCK_DELAY: 600
};

export default config;

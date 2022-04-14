import { ethers } from 'ethers';

const config = {
  MAINNET_DEPLOYMENT: false,
  CHAINLINK_FEE: ethers.utils.parseEther('10'),
  CHAINLINK_ORACLE_ADDRESS: '0x049bd8c3adc3fe7d3fc2a44541d955a537c2a484',
  ORACLE_PASS_THROUGH_ADDRESS: '', // TODO fill this in once deployed
  SCALING_PRICE_ORACLE_ADDRESS: '', // TODO fill this in once deployed
  MULTISIG_ADDRESS: '0x016177eDbB6809338Fda77b493cA01EA6D7Fc0D4',
  JOB_ID: ethers.utils.toUtf8Bytes('6f7fb4abcedb485ab27eb7bb39caf827'),
  CURRENT_MONTH_INFLATION_DATA: '287504',
  PREVIOUS_MONTH_INFLATION_DATA: '283716',
  MINT_FEE_BASIS_POINTS: 10, // Fee tentatively set at 10 basis points
  REDEEM_FEE_BASIS_POINTS: 0,
  DEPLOYER_VOLT_AMOUNT: ethers.utils.parseEther('42000000'), // 42m
  MAX_BUFFER_CAP: ethers.utils.parseEther('10000000'), // 10m
  MAX_BUFFER_CAP_MULTI_RATE_LIMITED: ethers.utils.parseEther('100000000'), // 100m
  RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('10000'), // 10k VOLT/s
  MAX_RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('100000'), // 100k VOLT/s
  GLOBAL_MAX_RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('100000'), // 100k VOLT/s
  PER_ADDRESS_MAX_RATE_LIMIT_PER_SECOND: ethers.utils.parseEther('15000'), // 15k VOLT/s
  PSM_BUFFER_CAP: ethers.utils.parseEther('10000000'), // 10m VOLT
  FEI: '0x956F47F50A910163D8BF957Cf5846D573E7f87CA',
  POOL_8_FEI: '0xd8553552f8868C1Ef160eEdf031cF0BCf9686945',
  ZERO_ADDRESS: ethers.constants.AddressZero
};

export default config;

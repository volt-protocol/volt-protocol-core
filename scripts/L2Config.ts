import { ethers } from 'ethers';

const l2config = {
  /// Decimal normalizers for PSMs

  /// Oracle price gets scaled up by 1e12 to account for the differences in decimals of USDC and VOLT.
  /// USDC has 6 decimals while Volt has 18, thus creating a difference of 12 that has to be normalized
  voltUSDCDecimalsNormalizer: 12,
  /// Oracle price does not need to be scaled up because both tokens have 18 decimals
  voltDAIDecimalsNormalizer: 0,
  reservesThreshold: ethers.constants.MaxUint256.toString(),

  /// Floor and ceiling are inverted due to oracle price inversion
  voltDAIFloorPrice: 9_000,
  voltDAICeilingPrice: 10_000,

  /// Need to scale up price of floor and ceiling by 1e12 to account for decimal normalizer that is factored into oracle price
  voltUSDCFloorPrice: '9000000000000000',
  voltUSDCCeilingPrice: '10000000000000000',

  voltPSMBufferCap: 0,
  mintLimitPerSecond: 0,

  ADDRESS_ONE: '0x0000000000000000000000000000000000000001',
  L2_REDEEM_FEE_BASIS_POINTS: 5,

  ACTUAL_START_TIME: '1655251723',
  STARTING_L2_ORACLE_PRICE: '1033724384083385655',

  /// Chainlink
  L2_ARBITRUM_JOB_ID: ethers.utils.toUtf8Bytes('db685451903340c590d22eb505d49946'),
  L2_ARBITRUM_CHAINLINK_FEE: ethers.utils.parseEther('1'), /// 1 Link to request data on L2
  L2_ARBITRUM_CHAINLINK_ORACLE_ADDRESS: '0xf76F586F6aAC0c8dE147Eea75D76AB7c2f23eDC2',
  L2_ARBITRUM_CHAINLINK_TOKEN: '0xf97f4df75117a78c1A5a0DBb814Af92458539FB4',

  L2_ARBITRUM_PREVIOUS_MONTH: '289109',
  L2_ARBITRUM_CURRENT_MONTH: '292296',

  L2_ARBITRUM_PROTOCOL_MULTISIG_ADDRESS: '0x1A1075cef632624153176CCf19Ae0175953CF010',
  L2_ARBITRUM_VOLT: '0x6Ba6f18a290Cd55cf1B00be2bEc5c954cb29fAc5',
  L2_DAI: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1', /// DAI has the same address on both Optimism and Arbitrum
  L2_ARBITRUM_USDC: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',

  /// Roles
  PCV_GUARD_ROLE: ethers.utils.id('PCV_GUARD_ROLE'),
  PCV_GUARD_ADMIN_ROLE: ethers.utils.id('PCV_GUARD_ADMIN_ROLE'),
  GOVERN_ROLE: ethers.utils.id('GOVERN_ROLE')
};

export default l2config;

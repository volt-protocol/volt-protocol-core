import { ethers } from 'ethers';
import { MainnetAddresses, AddressCategory, Network } from '../types/types'; // imported without custom path to allow docs to autogen without ts errors

const MainnetAddresses: MainnetAddresses = {
  fiewsChainlinkOracle: {
    address: '0x049bd8c3adc3fe7d3fc2a44541d955a537c2a484',
    artifactName: 'unknown',
    category: AddressCategory.Oracle,
    network: Network.Mainnet
  },
  arbitrumFiewsChainlinkOracle: {
    address: '0xf76F586F6aAC0c8dE147Eea75D76AB7c2f23eDC2',
    artifactName: 'unknown',
    category: AddressCategory.Oracle,
    network: Network.Arbitrum
  },
  scalingPriceOracle: {
    address: '0x79412660E95F94a4D2d02a050CEA776200939917',
    artifactName: 'OraclePassThrough',
    category: AddressCategory.Deprecated,
    network: Network.Mainnet
  },
  /// Current Volt System Oracle
  voltSystemOracle: {
    address: '0xD4546B5B7D28aE0E048c073DCD92358721CEA8D4',
    artifactName: 'VoltSystemOracle',
    category: AddressCategory.Oracle,
    network: Network.Mainnet
  },
  /// Current Volt System Oracle Pass Through
  voltSystemOraclePassThrough: {
    address: '0xe733985a92Bfd5BC676095561BacE90E04606E4a',
    artifactName: 'OraclePassThrough',
    category: AddressCategory.Oracle,
    network: Network.Mainnet
  },
  core: {
    address: '0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196',
    artifactName: 'Core',
    category: AddressCategory.Core,
    network: Network.Mainnet
  },
  volt: {
    address: '0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18',
    artifactName: 'Volt',
    category: AddressCategory.Core,
    network: Network.Mainnet
  },
  arbitrumVolt: {
    address: '0x6Ba6f18a290Cd55cf1B00be2bEc5c954cb29fAc5',
    artifactName: 'ERC20',
    category: AddressCategory.Core,
    network: Network.Arbitrum
  },
  fei: {
    address: '0x956F47F50A910163D8BF957Cf5846D573E7f87CA',
    artifactName: 'Volt',
    category: AddressCategory.Core,
    network: Network.Mainnet
  },
  arbitrumDai: {
    address: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
    artifactName: 'ERC20',
    category: AddressCategory.External,
    network: Network.Arbitrum
  },
  arbitrumUsdc: {
    address: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
    artifactName: 'ERC20',
    category: AddressCategory.External,
    network: Network.Arbitrum
  },
  globalRateLimitedMinter: {
    address: '0x87945f59E008aDc9ed6210a8e061f009d6ace718',
    artifactName: 'IGlobalRateLimitedMinter',
    category: AddressCategory.Core,
    network: Network.Mainnet
  },
  voltFusePCVDeposit: {
    address: '0xFeBDf448C8484834bb399d930d7E1bdC773E23bA',
    artifactName: 'ERC20CompoundPCVDeposit',
    category: AddressCategory.Deprecated,
    network: Network.Mainnet
  },
  feiFusePCVDeposit: {
    address: '0x4188fbD7aDC72853E3275F1c3503E170994888D7',
    artifactName: 'ERC20CompoundPCVDeposit',
    category: AddressCategory.Deprecated,
    network: Network.Mainnet
  },
  nonCustodialFusePSM: {
    address: '0x18f251FC3CE0Cb690F13f62213aba343657d0E72',
    artifactName: 'INonCustodialPSM',
    category: AddressCategory.Deprecated,
    network: Network.Mainnet
  },
  feiPriceBoundPSM: {
    address: '0x985f9C331a9E4447C782B98D6693F5c7dF8e560e',
    artifactName: 'PriceBoundPSM',
    category: AddressCategory.Peg,
    network: Network.Mainnet
  },
  usdcPriceBoundPSM: {
    address: '0x0b9A7EA2FCA868C93640Dd77cF44df335095F501',
    artifactName: 'PriceBoundPSM',
    category: AddressCategory.Peg,
    network: Network.Mainnet
  },
  daiPriceBoundPSM: {
    address: '0x42ea9cC945fca2dfFd0beBb7e9B3022f134d9Bdd',
    artifactName: 'PriceBoundPSM',
    category: AddressCategory.Peg,
    network: Network.Mainnet
  },
  makerRouter: {
    address: '0xC403da9AaC46d3AdcD1a1bBe774601C0ddc542F7',
    artifactName: 'MakerRouter',
    category: AddressCategory.PCV,
    network: Network.Mainnet
  },
  multisig: {
    address: '0x016177eDbB6809338Fda77b493cA01EA6D7Fc0D4',
    artifactName: 'unknown',
    category: AddressCategory.Governance,
    network: Network.Mainnet
  },
  protocolMultisig: {
    address: '0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf',
    artifactName: 'unknown',
    category: AddressCategory.Governance,
    network: Network.Mainnet
  },
  arbitrumProtocolMultisig: {
    address: '0x1A1075cef632624153176CCf19Ae0175953CF010',
    artifactName: 'unknown',
    category: AddressCategory.Governance,
    network: Network.Arbitrum
  },
  /// Volt Protocol Timelock
  timelockController: {
    address: '0x75d078248eE49c585b73E73ab08bb3eaF93383Ae',
    artifactName: 'TimelockController',
    category: AddressCategory.Governance,
    network: Network.Mainnet
  },
  optimisticTimelock: {
    address: '0x860fa85f04f9d35B3471D8F7F7fA3Ad31Ce4D5Ae',
    artifactName: 'TimelockController',
    category: AddressCategory.Deprecated,
    network: Network.Mainnet
  },
  makerDaiUsdcPSM: {
    address: '0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A',
    artifactName: 'unknown',
    category: AddressCategory.External,
    network: Network.Mainnet
  },
  feiDaiFixedPricePSM: {
    address: '0x2A188F9EB761F70ECEa083bA6c2A40145078dfc2',
    artifactName: 'unknown', /// Fixed Price PSM
    category: AddressCategory.External,
    network: Network.Mainnet
  },
  feiDAOTimelock: {
    address: '0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c',
    artifactName: 'unknown', /// FeiDAOTimelock
    category: AddressCategory.External,
    network: Network.Mainnet
  },
  tribalCouncilTimelock: {
    address: '0xe0C7DE94395B629860Cbb3c42995F300F56e6d7a',
    artifactName: 'unknown', /// Timelock Controller
    category: AddressCategory.External,
    network: Network.Mainnet
  },
  feiVoltOTCSwap: {
    address: '0xeF152E462B59940616E667E801762dA9F2AF97b9',
    artifactName: 'OtcEscrow',
    category: AddressCategory.External,
    network: Network.Mainnet
  },
  otcEscrowRepayment: {
    address: '0x590eb1a809377f786a11fa1968eF8c15eB44A12F',
    artifactName: 'OtcEscrow',
    category: AddressCategory.External,
    network: Network.Mainnet
  },
  dai: {
    address: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    artifactName: 'ERC20',
    category: AddressCategory.External,
    network: Network.Mainnet
  },
  usdc: {
    address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    artifactName: 'ERC20',
    category: AddressCategory.External,
    network: Network.Mainnet
  },
  pool8Fei: {
    address: '0xd8553552f8868C1Ef160eEdf031cF0BCf9686945',
    artifactName: 'unknown', /// CErc20Delegator
    category: AddressCategory.External,
    network: Network.Mainnet
  },
  pcvGuardian: {
    address: '0x2c2b362e6ae0F080F39b90Cb5657E5550090D6C3',
    artifactName: 'PCVGuardian',
    category: AddressCategory.Guardian,
    network: Network.Mainnet
  },
  pcvGuardAdmin: {
    address: '0x868F58Ae8F6B2Dc31D9ADc97a8A09B16f05E9cd7',
    artifactName: 'PCVGuardAdmin',
    category: AddressCategory.External,
    network: Network.Mainnet
  },
  pcvGuardEOA1: {
    address: '0xB320e376Be6459421695F2b6B1E716AE4bc8129A',
    artifactName: 'unknown',
    category: AddressCategory.Guardian,
    network: Network.Mainnet
  },
  pcvGuardEOA2: {
    address: '0xd90E9181B20D8D1B5034d9f5737804Da182039F6',
    artifactName: 'unknown',
    category: AddressCategory.Guardian,
    network: Network.Mainnet
  },
  pcvGuardEOA3: {
    address: '0xA96D4a5c343d6fE141751399Fc230E9E8Ecb6fb6',
    artifactName: 'unknown',
    category: AddressCategory.Guardian,
    network: Network.Mainnet
  },
  pcvGuardRevoked1: {
    address: '0xf8D0387538E8e03F3B4394dA89f221D7565a28Ee',
    artifactName: 'unknown',
    category: AddressCategory.Deprecated,
    network: Network.Mainnet
  },
  arbitrumCore: {
    address: '0x31A38B79fDcFBC3095E3268CAFac1b9791796736',
    artifactName: 'L2Core',
    category: AddressCategory.Core,
    network: Network.Arbitrum
  },
  arbitrumOptimisticTimelock: {
    address: '0x980A05105a53eCa7745DA40DF1AdE6674fc73eD5',
    artifactName: 'TimelockController',
    category: AddressCategory.Deprecated,
    network: Network.Arbitrum
  },
  arbitrumTimelockController: {
    address: '0x2c01C9166FA3e16c24c118053E346B1DD8e72dE8',
    artifactName: 'TimelockController',
    category: AddressCategory.Governance,
    network: Network.Arbitrum
  },

  /// Deprecated Arbitrum L2 Scaling Price Oracle
  arbitrumScalingPriceOracle: {
    address: '0x138F30D35557FA72478663b601f0f0FD7cc4E39E',
    artifactName: 'L2ScalingPriceOracle',
    category: AddressCategory.Deprecated,
    network: Network.Arbitrum
  },

  arbitrumVoltSystemOracle: {
    address: '0x69DBf8dD98Aa40F50E4f2263c6f2d66f26f9cb5b',
    artifactName: 'VoltSystemOracle',
    category: AddressCategory.Oracle,
    network: Network.Arbitrum
  },
  arbitrumOraclePassThrough: {
    address: '0xcd836280e4416e08F54E5584Bcd49Ac2E3a68747',
    artifactName: 'OraclePassThrough',
    category: AddressCategory.Oracle,
    network: Network.Arbitrum
  },

  arbitrumPCVGuardAdmin: {
    address: '0x0d6d0600BEa83FaAF172C2E8aCDd2F5140e235D3',
    artifactName: 'PCVGuardAdmin',
    category: AddressCategory.TBD,
    network: Network.Arbitrum
  },
  arbitrumPCVGuardian: {
    address: '0x14eCB5Ff2A78364E0FF443B7F0F6e0e393531484',
    artifactName: 'PCVGuardian',
    category: AddressCategory.Guardian,
    network: Network.Arbitrum
  },
  arbitrumDAIPSM: {
    address: '0x4d2cF840FDe4210A96F485fC01f1459Bfb2EFABb',
    artifactName: 'PriceBoundPSM',
    category: AddressCategory.Peg,
    network: Network.Arbitrum
  },
  arbitrumUSDCPSM: {
    address: '0x278A903dA9Fb0ea8B90c2b1b089eF90033FDd868',
    artifactName: 'PriceBoundPSM',
    category: AddressCategory.Peg,
    network: Network.Arbitrum
  },
  zeroAddress: {
    address: ethers.constants.AddressZero,
    artifactName: 'unknown',
    category: AddressCategory.TBD,
    network: Network.Mainnet
  }
};

export default MainnetAddresses;

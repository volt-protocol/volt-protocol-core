import { ethers } from 'ethers';
import { MainnetAddresses, AddressCategory } from '../types/types'; // imported without custom path to allow docs to autogen without ts errors

const MainnetAddresses: MainnetAddresses = {
  fiewsChainlinkOracle: {
    address: '0x049bd8c3adc3fe7d3fc2a44541d955a537c2a484',
    artifactName: 'unknown',
    category: AddressCategory.Oracle
  },
  oraclePassThrough: {
    address: '0x84dc71500D504163A87756dB6368CC8bB654592f',
    artifactName: 'OraclePassThrough',
    category: AddressCategory.Oracle
  },
  scalingPriceOracle: {
    address: '0x79412660E95F94a4D2d02a050CEA776200939917',
    artifactName: 'OraclePassThrough',
    category: AddressCategory.Oracle
  },
  core: {
    address: '0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196',
    artifactName: 'Core',
    category: AddressCategory.Core
  },
  volt: {
    address: '0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18',
    artifactName: 'Volt',
    category: AddressCategory.Core
  },
  fei: {
    address: '0x956F47F50A910163D8BF957Cf5846D573E7f87CA',
    artifactName: 'Volt',
    category: AddressCategory.Core
  },
  globalRateLimitedMinter: {
    address: '0x87945f59E008aDc9ed6210a8e061f009d6ace718',
    artifactName: 'GlobalRateLimitedMinter',
    category: AddressCategory.Core
  },
  voltFusePCVDeposit: {
    address: '0xFeBDf448C8484834bb399d930d7E1bdC773E23bA',
    artifactName: 'ERC20CompoundPCVDeposit',
    category: AddressCategory.Deprecated
  },
  feiFusePCVDeposit: {
    address: '0x4188fbD7aDC72853E3275F1c3503E170994888D7',
    artifactName: 'ERC20CompoundPCVDeposit',
    category: AddressCategory.Deprecated
  },
  nonCustodialFusePSM: {
    address: '0x18f251FC3CE0Cb690F13f62213aba343657d0E72',
    artifactName: 'NonCustodialPSM',
    category: AddressCategory.Deprecated
  },
  feiPriceBoundPSM: {
    address: '0x985f9C331a9E4447C782B98D6693F5c7dF8e560e',
    artifactName: 'PriceBoundPSM',
    category: AddressCategory.Peg
  },
  usdcPriceBoundPSM: {
    address: '0x0b9A7EA2FCA868C93640Dd77cF44df335095F501',
    artifactName: 'PriceBoundPSM',
    category: AddressCategory.Peg
  },
  multisig: {
    address: '0x016177eDbB6809338Fda77b493cA01EA6D7Fc0D4',
    artifactName: 'unknown',
    category: AddressCategory.Governance
  },
  protocolMultisig: {
    address: '0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf',
    artifactName: 'unknown',
    category: AddressCategory.Governance
  },
  /// Volt Protocol Timelock
  optimisticTimelock: {
    address: '0x860fa85f04f9d35B3471D8F7F7fA3Ad31Ce4D5Ae',
    artifactName: 'OptimisticTimelock',
    category: AddressCategory.Governance
  },
  feiDaiFixedPricePSM: {
    address: '0x2A188F9EB761F70ECEa083bA6c2A40145078dfc2',
    artifactName: 'unknown', /// Fixed Price PSM
    category: AddressCategory.External
  },
  feiDAOTimelock: {
    address: '0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c',
    artifactName: 'unknown', /// FeiDAOTimelock
    category: AddressCategory.External
  },
  feiVoltOTCSwap: {
    address: '0xeF152E462B59940616E667E801762dA9F2AF97b9',
    artifactName: 'OtcEscrow',
    category: AddressCategory.External
  },
  dai: {
    address: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    artifactName: 'ERC20',
    category: AddressCategory.External
  },
  usdc: {
    address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    artifactName: 'ERC20',
    category: AddressCategory.External
  },
  pool8Fei: {
    address: '0xd8553552f8868C1Ef160eEdf031cF0BCf9686945',
    artifactName: 'unknown', /// CErc20Delegator
    category: AddressCategory.External
  },
  pcvGuardian: {
    address: '0x2c2b362e6ae0F080F39b90Cb5657E5550090D6C3',
    artifactName: 'PCVGuardian',
    category: AddressCategory.Guardian
  },
  pcvGuardAdmin: {
    address: '0x868F58Ae8F6B2Dc31D9ADc97a8A09B16f05E9cd7',
    artifactName: 'PCVGuardAdmin',
    category: AddressCategory.External
  },
  pcvGuardEOA1: {
    address: '0xf8D0387538E8e03F3B4394dA89f221D7565a28Ee',
    artifactName: 'unknown',
    category: AddressCategory.Guardian
  },
  pcvGuardEOA2: {
    address: '0xd90E9181B20D8D1B5034d9f5737804Da182039F6',
    artifactName: 'OtcEscrow',
    category: AddressCategory.Guardian
  },
  zeroAddress: {
    address: ethers.constants.AddressZero,
    artifactName: 'unknown',
    category: AddressCategory.TBD
  }
};

export default MainnetAddresses;

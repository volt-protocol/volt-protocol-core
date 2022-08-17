import { BigNumber, ethers } from 'ethers';
import {
  Core,
  Volt,
  IERC20,
  Vcon,
  L2Core,
  PCVGuardAdmin,
  PCVGuardian,
  OraclePassThrough,
  PriceBoundPSM,
  TimelockController
} from './contracts';

export type Env = {
  contracts: NamedContracts;
  contractAddresses: NamedAddresses;
};

export type ExtendedAlphaProposal = {
  targets: string[];
  values: BigNumber[];
  signatures: string[];
  calldatas: string[];
  description: string;
};

export interface TestCoordinator {
  loadEnvironment(): Promise<Env>;
}

export function namedContractsToNamedAddresses(contracts: NamedContracts): NamedAddresses {
  const namedAddresses: NamedAddresses = {};

  Object.keys(contracts).map(function (contractName) {
    namedAddresses[contractName] = contracts[contractName].address;
  });

  return namedAddresses;
}

export type Dependency = {
  contractDependencies: string[];
};
export type DependencyMap = { [key: string]: Dependency };

export enum ProposalCategory {
  DAO,
  OA,
  None
}

export type ProposalConfig = {
  deploy: boolean;
  category: ProposalCategory;
  totalValue: number;
  proposal: ProposalDescription;
  affectedContractSignoff: string[];
  deprecatedContractSignoff: string[];
  proposalId: string;
};

export type ProposalsConfigMap = {
  [key: string]: ProposalConfig;
};

export type ProposalDescription = {
  title: string;
  commands: ProposalCommand[];
  description: string;
};

export type ProposalCommand = {
  target: string;
  values: string;
  method: string;
  arguments: any[];
  description: string;
};

export interface MainnetAddresses {
  [key: string]: AddressConfig;
}

export interface KovanAddresses {
  [key: string]: AddressConfigKovan;
}

export interface AddressConfigKovan {
  artifactName: string;
  address: string;
}

export interface AddressConfig {
  artifactName: string;
  address: string;
  category: AddressCategory;
  network: Network;
}

export enum Network {
  Mainnet = 'Mainnet',
  Arbitrum = 'Arbitrum'
}

export enum AddressCategory {
  Core = 'Core',
  Governance = 'Governance',
  Guardian = 'Guardian',
  Peg = 'Peg',
  PCV = 'PCV',
  PCV_V1 = 'PCV_V1',
  Collateralization = 'Collateralization',
  Oracle = 'Oracle',
  Keeper = 'Keeper',
  Rewards = 'Rewards',
  FeiRari = 'FeiRari',
  External = 'External',
  Deprecated = 'Deprecated',
  TBD = 'TBD'
}

export type NamedContracts = { [key: string]: ethers.Contract };
export type NamedAddresses = { [key: string]: string };
export type DeployUpgradeFunc = (
  deployAddress: string,
  address: NamedAddresses,
  logging: boolean
) => Promise<NamedContracts>;
export type SetupUpgradeFunc = (
  addresses: NamedAddresses,
  oldContracts: NamedContracts,
  contracts: NamedContracts,
  logging: boolean
) => Promise<void>;
export type RunUpgradeFunc = (
  addresses: NamedAddresses,
  oldContracts: NamedContracts,
  contracts: NamedContracts,
  logging: boolean
) => Promise<void>;
export type TeardownUpgradeFunc = (
  addresses: NamedAddresses,
  oldContracts: NamedContracts,
  contracts: NamedContracts,
  logging: boolean
) => Promise<void>;
export type ValidateUpgradeFunc = (
  addresses: NamedAddresses,
  oldContracts: NamedContracts,
  contracts: NamedContracts,
  logging: boolean
) => Promise<void>;

export type UpgradeFuncs = {
  deploy: DeployUpgradeFunc;
  setup: SetupUpgradeFunc;
  run: RunUpgradeFunc;
  teardown: TeardownUpgradeFunc;
  validate: ValidateUpgradeFunc;
};

export type Config = {
  version: number;
  deployAddress: string;
  logging: boolean;
};

export interface MainnetContracts {
  core: Core;
  tribe: Vcon;
  fei: Volt;
  Vcon: Vcon;
  Volt: Volt;
  uniswapPCVController: ethers.Contract;
  curveMetapoolDeposit: ethers.Contract;
  curveMetapool: ethers.Contract;
  curve3pool: ethers.Contract;
  curve3crv: ethers.Contract;
  stAAVE: IERC20;
  dpi: IERC20;
  dai: IERC20;
  rai: IERC20;
  timelockController: TimelockController;
  arbitrumTimelockController: TimelockController;
  optimisticTimelock: TimelockController;
  optimisticTimelockArbitrum: TimelockController;
  curve3Metapool: IERC20;
  arbitrumOptimisticTimelock: TimelockController;
  arbitrumCore: L2Core;
  arbitrumPCVGuardAdmin: PCVGuardAdmin;
  arbitrumPCVGuardian: PCVGuardian;
  arbitrumOraclePassThrough: OraclePassThrough;
  arbitrumDAIPSM: PriceBoundPSM;
  arbitrumUSDCPSM: PriceBoundPSM;
}

export interface MainnetContractAddresses {
  core: string;
  tribe: string;
  fei: string;
  uniswapPCVDeposit: string;
  chainlinkEthUsdOracle: string;
  chainlinkFeiEthOracle: string;
  compositeOracle: string;
  compoundDai: string;
  ethReserveStabilizer: string;
  ratioPCVController: string;
  weth: string;
  uniswapRouter: string;
  feiEthPair: string;
  uniswapOracle: string;
  feiRewardsDistributor: string;
  tribeReserveStabilizer: string;
  timelock: string;
  multisig: string;
  governorAlpha: string;
  indexCoopFusePoolDpi: string;
  reflexerStableAssetFusePoolRai: string;
  feiTribePair: string;
  arbitrumProtocolMultisig: string;
}

export type ContractAccessRights = {
  minter: string[];
  burner: string[];
  governor: string[];
  pcvController: string[];
  guardian: string[];
};

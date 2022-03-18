import { DependencyMap } from '../types/types';

/// TODO figure out all the deps that aren't here
const dependencies: DependencyMap = {
  core: {
    contractDependencies: [
      'fei',
      'feiTribeLBPSwapper',
      'optimisticMinter',
      'pcvEquityMinter',
      'pcvGuardian',
      'ratioPCVControllerV2',
      'tribe',
      'tribeMinter',
      'feiDAOTimelock',
      'guardian',
      'optimisticTimelock',
      'aaveEthPCVDripController',
      'bammDeposit',
      'daiPCVDripController',
      'daiPSM',
      'ethPSM',
      'lusdPSM'
    ]
  },
  fei: {
    contractDependencies: [
      'core',
      'rariPool8Fei',
      'feiDAOTimelock',
      'collateralizationOracleKeeper',
      'aaveEthPCVDripController',
      'daiPSM'
    ]
  },
  tribe: {
    contractDependencies: ['core']
  },
  feiDAO: {
    contractDependencies: ['feiDAOTimelock', 'tribe']
  },
  feiDAOTimelock: {
    contractDependencies: ['core', 'feiDAO', 'fei']
  },
  guardian: {
    contractDependencies: ['core', 'fuseAdmin']
  }
};

export default dependencies;

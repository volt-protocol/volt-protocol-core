import { HardhatUserConfig } from 'hardhat/config';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-ethers';
import '@typechain/hardhat';
import '@idle-finance/hardhat-proposals-plugin';
import 'solidity-coverage';
import 'tsconfig-paths/register';

import * as dotenv from 'dotenv';

dotenv.config();

const rinkebyAlchemyApiKey = process.env.RINKEBY_ALCHEMY_API_KEY;
const kovanAlchemyApiKey = process.env.KOVAN_ALCHEMY_API_KEY;
const testnetPrivateKey = process.env.TESTNET_PRIVATE_KEY;
const privateKey = process.env.ETH_PRIVATE_KEY;
const enableMainnetForking = process.env.ENABLE_MAINNET_FORKING;
const enableArbitrumForking = process.env.ENABLE_ARBITRUM_FORKING;
const mainnetAlchemyApiKey = process.env.MAINNET_ALCHEMY_API_KEY;
const arbitrumAlchemyApiKey = process.env.ARBITRUM_ALCHEMY_API_KEY;
const useJSONTestReporter = process.env.REPORT_TEST_RESULTS_AS_JSON;

if (enableMainnetForking) {
  if (!mainnetAlchemyApiKey) {
    throw new Error('Cannot fork mainnet without mainnet alchemy api key.');
  }

  console.log('Mainnet forking enabled.');
} else {
  console.log('Mainnet forking disabled.');
}

if (useJSONTestReporter) {
  console.log(`Reporting test results as JSON, you will not see them in the console.`);
}

export default {
  etherscan: {
    apiKey: {
      // Your API key for Etherscan
      // Obtain one at https://etherscan.io/ or https://arbiscan.io/
      mainnet: process.env.ETHERSCAN_KEY,
      arbitrumOne: process.env.ARBISCAN_KEY
    }
  },
  gasReporter: {
    enabled: !!process.env.REPORT_GAS
  },
  networks: {
    hardhat: {
      gas: 12e6,
      chainId: 5777, // Any network (default: none)
      forking: enableMainnetForking
        ? {
            url: `https://eth-mainnet.alchemyapi.io/v2/${mainnetAlchemyApiKey}`,
            blockNumber: 15175278
          }
        : enableArbitrumForking
        ? {
            url: `https://arb-mainnet.g.alchemy.com/v2/${arbitrumAlchemyApiKey}`
          }
        : undefined
    },

    localhost: {
      accounts: testnetPrivateKey ? [testnetPrivateKey] : [],
      url: 'http://127.0.0.1:8545'
    },

    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${kovanAlchemyApiKey}`,
      accounts: testnetPrivateKey ? [testnetPrivateKey] : [],
      gasPrice: 20000000000 // gas price that is paid for kovan transactions. currently 20 gigawei
    },

    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${rinkebyAlchemyApiKey}`,
      accounts: testnetPrivateKey ? [testnetPrivateKey] : []
    },

    arbitrumOne: {
      url: `https://arb-mainnet.g.alchemy.com/v2/${arbitrumAlchemyApiKey}`,
      accounts: privateKey ? [privateKey] : [],
      gasPrice: 1000000000 // gas price that is paid for arbitrum transactions. currently .9 gigawei
    },

    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${mainnetAlchemyApiKey}`,
      accounts: privateKey ? [privateKey] : [],
      gasPrice: 40000000000 // gas price that is paid for mainnet transactions. currently 40 gigawei
    }
  },

  solidity: {
    compilers: [
      {
        version: '0.8.10',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: '0.8.13',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: '0.4.18',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },

  mocha: {
    timeout: 1000000,
    reporter: useJSONTestReporter ? 'mocha-multi-reporters' : undefined,
    reporterOptions: useJSONTestReporter
      ? {
          configFile: 'mocha-reporter-config.json'
        }
      : undefined
  },

  typechain: {
    outDir: './types/contracts/',
    target: 'ethers-v5',
    alwaysGenerateOverloads: false // should overloads with full signatures like deposit(uint256) be generated always, even if there are no overloads?
  }
} as HardhatUserConfig;

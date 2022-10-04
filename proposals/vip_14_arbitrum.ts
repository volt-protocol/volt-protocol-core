import { ProposalDescription } from '@custom-types/types';

const vip_14_arbitrum: ProposalDescription = {
  title: 'VIP-14 Arbitrum: Rate Update to 0, Pause PSM Minting',
  commands: [
    {
      target: 'arbitrumOraclePassThrough',
      values: '0',
      method: 'updateScalingPriceOracle(address)',
      arguments: ['{voltSystemOracle0Bips}'],
      description: 'Point Arbitrum Oracle Pass Through to 0 basis point Volt System Oracle'
    },
    {
      target: 'arbitrumUSDCPSM',
      values: '0',
      method: 'pauseMint()',
      arguments: [],
      description: 'Pause minting on USDC PSM on Arbitrum'
    },
    {
      target: 'arbitrumDAIPSM',
      values: '0',
      method: 'pauseMint()',
      arguments: [],
      description: 'Pause minting on DAI PSM on Arbitrum'
    }
  ],
  description: `
  Deployment Steps
  1. deploy volt system oracle
  
  Governance Steps:
  1. Point Oracle Pass Through to new oracle address
  2. Pause minting on DAI PSM on Arbitrum
  3. Pause minting on USDC PSM on Arbitrum
  `
};

export default vip_14_arbitrum;

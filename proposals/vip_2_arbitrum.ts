import { ProposalDescription } from '@custom-types/types';

const vip_2: ProposalDescription = {
  title: 'VIP-2: New Oracle Upgrade on Arbitrum',
  commands: [
    {
      target: 'arbitrumDAIPSM',
      values: '0',
      method: 'setOracle(address)',
      arguments: ['{oraclePassThroughArbitrum}'],
      description: 'Set oracle pass through on DAI PSM'
    },
    {
      target: 'arbitrumUSDCPSM',
      values: '0',
      method: 'setOracle(address)',
      arguments: ['{oraclePassThroughArbitrum}'],
      description: 'Set oracle pass through on USDC PSM'
    },
    {
      target: 'arbitrumDAIPSM',
      values: '0',
      method: 'setMintFee(uint256)',
      arguments: ['5'],
      description: 'Set mint fee to 5 basis points'
    },
    {
      target: 'arbitrumUSDCPSM',
      values: '0',
      method: 'setMintFee(uint256)',
      arguments: ['5'],
      description: 'Set mint fee to 5 basis points'
    }
  ],
  description: `
  Point both DAI and USDC PSM to the new OraclePassThrough contract, set mint and redeem fee to 5 basis points
  `
};

export default vip_2;

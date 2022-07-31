import { ProposalDescription } from '@custom-types/types';

const vip_2: ProposalDescription = {
  title: 'VIP-2: New Oracle Upgrade',
  commands: [
    /// set updated oracles
    {
      target: 'usdcPriceBoundPSM',
      values: '0',
      method: 'setOracle(address)',
      arguments: ['{oraclePassThrough}'],
      description: 'Set Oracle Pass Through on USDC PSM'
    },
    {
      target: 'feiPriceBoundPSM',
      values: '0',
      method: 'setOracle(address)',
      arguments: ['{oraclePassThrough}'],
      description: 'Set oracle pass through on FEI PSM'
    },
    /// reduce mint fee to 0
    {
      target: 'usdcPriceBoundPSM',
      values: '0',
      method: 'setMintFee(uint256)',
      arguments: ['0'],
      description: 'Set mint fee to 0'
    },
    {
      target: 'feiPriceBoundPSM',
      values: '0',
      method: 'setMintFee(uint256)',
      arguments: ['0'],
      description: 'Set mint fee to 0'
    }
  ],
  description: `Point both FEI and USDC PSM to the new OraclePassThrough contract and set mint fee to 0 on both PSMs`
};

export default vip_2;

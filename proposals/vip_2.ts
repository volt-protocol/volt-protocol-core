import { ProposalDescription } from '@custom-types/types';

const vip_2: ProposalDescription = {
  title: 'VIP-2: New Oracle Upgrade',
  commands: [
    {
      target: 'usdcPriceBoundPSM',
      values: '0',
      method: 'setOracle(address)',
      arguments: ['{oraclePassThrough}'],
      description: 'Set oracle pass through on USDC PSM'
    },
    {
      target: 'feiPriceBoundPSM',
      values: '0',
      method: 'setOracle(address)',
      arguments: ['{oraclePassThrough}'],
      description: 'Set oracle pass through on FEI PSM'
    }
  ],
  description: `Point both FEI and USDC PSM to the new OraclePassThrough contract`
};

export default vip_2;

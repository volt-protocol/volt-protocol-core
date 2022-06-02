import { ProposalDescription } from '@custom-types/types';

const vip_2: ProposalDescription = {
  title: 'VIP-2: Check if core is governor',
  commands: [
    {
      target: 'core',
      values: '0',
      method: 'isGovernor(address)',
      arguments: ['{core}'],
      description: 'Check if core is governor'
    }
  ],
  description: `Check if core is governor`
};

export default vip_2;

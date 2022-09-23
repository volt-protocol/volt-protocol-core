import { ProposalDescription } from '@custom-types/types';

const vip_12: ProposalDescription = {
  title: 'VIP-12: Compound PCV Router',
  commands: [
    {
      target: 'core',
      values: '0',
      method: 'grantPCVController(address)',
      arguments: ['{compoundPCVRouter}'],
      description: 'Grant Compound PCV Router the PCV Controller Role'
    }
  ],
  description: 'VIP-12 Grant Compound PCV Router the PCV Controller Role'
};

export default vip_12;

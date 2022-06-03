import { ProposalDescription } from '@custom-types/types';

const vip_1: ProposalDescription = {
  title: 'VIP-1: Setup Timelock',
  commands: [
    {
      target: 'core',
      values: '0',
      method: 'grantPCVController(address)',
      arguments: ['{optimisticTimelock}'],
      description: 'Grant timelock PCV Controller role'
    }
  ],
  description: `Grant the Timelock PCV Controller Role`
};

export default vip_1;

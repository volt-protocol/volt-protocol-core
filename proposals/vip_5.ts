import { ProposalDescription } from '@custom-types/types';

const vip_5: ProposalDescription = {
  title: 'VIP-5: Burn Deprecated Timelock VOLT',
  commands: [
    {
      target: 'volt',
      values: '0',
      method: 'burn(uint256)',
      arguments: ['10000000000000000000000000'],
      description: 'Burn 10m VOLT in deprecated timelock'
    }
  ],
  description: 'Burn 10m VOLT collateral from Tribe DAO loan'
};

export default vip_5;

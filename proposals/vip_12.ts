import { ProposalDescription } from '@custom-types/types';

const vip_x: ProposalDescription = {
  title: 'VIP-12: Add new PSMs to PCV Guardian Whitelist',
  commands: [
    {
      target: 'pcvGuardian',
      values: '0',
      method: 'addWhitelistAddresses(address[])',
      arguments: [['{voltV2DaiPriceBoundPSM}', '{voltV2UsdcPriceBoundPSM}']],
      description: 'Add new DAI, and USDC PSMs to PCV Guardian whitelist'
    }
  ],
  description: 'Add new DAI, and USDC PSMs to PCV Guardian whitelist'
};

export default vip_x;

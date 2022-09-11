import { ProposalDescription } from '@custom-types/types';

const vip_10: ProposalDescription = {
  title: 'VIP-10: ERC20 Allocator Deployment',
  commands: [
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'connectPSM(address,address,uint248,int8)',
      arguments: ['{usdcPriceBoundPSM}', '{usdcCompoundPCVDeposit}', '100000000000', '12'],
      description: 'Add USDC deposit to the ERC20 Allocator'
    },
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'connectPSM(address,address,uint248,int8)',
      arguments: ['{daiPriceBoundPSM}', '{daiCompoundPCVDeposit}', '100000000000000000000000', '0'],
      description: 'Add DAI deposit to the ERC20 Allocator'
    },
    {
      target: 'core',
      values: '0',
      method: 'grantPCVController(address)',
      arguments: ['{erc20Allocator}'],
      description: 'Grant PCV Controller to the erc20Allocator'
    }
  ],
  description: 'Create ERC20Allocator, add DAI and USDC psm and compound pcv deposit to the allocator'
};

export default vip_10;

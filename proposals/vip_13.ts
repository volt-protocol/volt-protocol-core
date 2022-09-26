import { ProposalDescription } from '@custom-types/types';

const vip_13: ProposalDescription = {
  title: 'VIP-13: Add new PSMs to PCV Guardian Whitelist',
  commands: [
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'disconnectPSM(address)',
      arguments: ['{usdcPriceBoundPSM}'],
      description: 'Disconnet USDC PSM from the ERC20 Allocator'
    },
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'disconnectPSM(address)',
      arguments: ['{daiPriceBoundPSM}'],
      description: 'Disconnet DAI PSM from the ERC20 Allocator'
    },
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'connectPSM(address,uint248,int8)',
      arguments: ['{voltV2UsdcPriceBoundPSM}', '100000000000', '12'],
      description: 'Add USDC PSM to the ERC20 Allocator'
    },
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'connectPSM(address,uint248,int8)',
      arguments: ['{voltV2DaiPriceBoundPSM}', '100000000000000000000000', '0'],
      description: 'Add DAI PSM to the ERC20 Allocator'
    },
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'connectDeposit(address,address)',
      arguments: ['{voltV2UsdcPriceBoundPSM}', '{usdcCompoundPCVDeposit}'],
      description: 'Connect USDC deposit to PSM in ERC20 Allocator'
    },
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'connectDeposit(address,address)',
      arguments: ['{voltV2daiPriceBoundPSM}', '{daiCompoundPCVDeposit}'],
      description: 'Connect DAI deposit to PSM in ERC20 Allocator'
    },
    {
      target: 'pcvGuardian',
      values: '0',
      method: 'addWhitelistAddresses(address[])',
      arguments: [['{voltV2UsdcPriceBoundPSM}', '{voltV2DaiPriceBoundPSM}']],
      description: 'Add new DAI, and USDC PSMs to PCV Guardian whitelist'
    }
  ],
  description: 'Add new DAI, and USDC PSMs to PCV Guardian whitelist'
};

export default vip_13;

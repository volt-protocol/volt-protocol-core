import { ProposalDescription } from '@custom-types/types';

const vip_13: ProposalDescription = {
  title: 'VIP-13: Add new PSMs to PCV Guardian Whitelist',
  commands: [
    {
      target: 'core',
      values: '0',
      method: 'grantMinter(address)',
      arguments: ['{timelockController}'],
      description: 'Grant minter role to timelock'
    },
    {
      target: 'voltV2',
      values: '0',
      method: 'mint(address,uint256)',
      arguments: ['{voltMigrator}', '1000000000000'], // placeholder value
      description: 'Mint new volt for new VOLT to migrator contract'
    },
    {
      target: 'core',
      values: '0',
      method: 'revokeMinter(address)',
      arguments: ['{timelockController}'],
      description: 'Revoke minter role to timelock'
    },
    {
      target: 'volt',
      values: '0',
      method: 'approve(address,uint256)',
      arguments: ['{voltMigrator}', '1000000000000'], // placeholder value
      description: 'Approve migrator to use VOLT'
    },
    {
      target: 'voltMigrator',
      values: '0',
      method: 'exchangeTo(address,uint256)',
      arguments: ['{voltV2UsdcPriceBoundPSM}', '1000000000000'], // placeholder value
      description: 'Exchange new volt for new USDC PSM'
    },
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'exchangeTo(address,uint256)',
      arguments: ['{voltV2DaiPriceBoundPSM}', '1000000000000'], // placeholder value
      description: 'Exchange new volt for new DAI PSM'
    },
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
      arguments: ['{voltV2DaiPriceBoundPSM}', '{daiCompoundPCVDeposit}'],
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
  description:
    'Mint Volt total supply to migrator contract, fund new DAI and USDC PSMs with new Volt, connect new PSMs to the ERC20 Allocator, and add new DAI, and USDC PSMs to PCV Guardian whitelist'
};

export default vip_13;

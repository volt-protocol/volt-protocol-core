import { ProposalDescription } from '@custom-types/types';

const vip_14: ProposalDescription = {
  title: 'VIP-14: Morpho PCV Deposit',
  commands: [
    /// core actions
    {
      target: 'core',
      values: '0',
      method: 'grantPCVController(address)',
      arguments: ['{morphoCompoundPCVRouter}'],
      description: 'Grant Morpho PCV Router PCV Controller Role'
    },
    {
      target: 'core',
      values: '0',
      method: 'revokePCVController(address)',
      arguments: ['{compoundPCVRouter}'],
      description: 'Revoke PCV Controller Role from Compound PCV Router'
    },
    /// allocator actions
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'deleteDeposit(address)',
      arguments: ['{daiCompoundPCVDeposit}'],
      description: 'Remove Compound DAI Deposit from ERC20Allocator'
    },
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'deleteDeposit(address)',
      arguments: ['{usdcCompoundPCVDeposit}'],
      description: 'Remove Compound USDC Deposit from ERC20Allocator'
    },
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'connectDeposit(address,address)',
      arguments: ['{daiPriceBoundPSM}', '{daiMorphoCompoundPCVDeposit}'],
      description: 'Add Morpho DAI Deposit to ERC20Allocator'
    },
    {
      target: 'erc20Allocator',
      values: '0',
      method: 'connectDeposit(address,address)',
      arguments: ['{usdcPriceBoundPSM}', '{usdcMorphoCompoundPCVDeposit}'],
      description: 'Add Morpho USDC Deposit to ERC20Allocator'
    },
    /// pcv guardian action
    {
      target: 'pcvGuardian',
      values: '0',
      method: 'addWhitelistAddresses(address[])',
      arguments: [['{daiMorphoCompoundPCVDeposit}', '{usdcMorphoCompoundPCVDeposit}']],
      description: 'Add USDC and DAI Morpho deposits to the PCV Guardian'
    },
    {
      target: 'daiCompoundPCVDeposit',
      values: '0',
      method: 'pause()',
      arguments: [],
      description: 'Pause Compound DAI PCV Deposit'
    },
    {
      target: 'usdcCompoundPCVDeposit',
      values: '0',
      method: 'pause()',
      arguments: [],
      description: 'Pause Compound USDC PCV Deposit'
    }
  ],
  description: `
  Deployment Steps
   1. deploy morpho dai deposit
   2. deploy morpho usdc deposit
   3. deploy compound pcv router pointed to morpho dai and usdc deposits
  
  Governance Steps:
  1. Grant Morpho PCV Router PCV Controller Role
  2. Revoke PCV Controller Role from Compound PCV Router
  3. Remove Compound DAI Deposit from ERC20Allocator
  4. Remove Compound USDC Deposit from ERC20Allocator
  5. Add Morpho DAI Deposit to ERC20Allocator
  6. Add Morpho USDC Deposit to ERC20Allocator
  7. Add USDC and DAI Morpho deposits to the PCV Guardian
  8. pause dai compound pcv deposit
  9. pause usdc compound pcv deposit
  `
};

export default vip_14;

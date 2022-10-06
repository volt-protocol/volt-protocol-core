import { ProposalDescription } from '@custom-types/types';

const vip_14: ProposalDescription = {
  title: 'VIP-14: Morpho Maple PCV Deposit, Rate Update',
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
      arguments: [['{daiMorphoCompoundPCVDeposit}', '{usdcMorphoCompoundPCVDeposit}', '{maplePCVDeposit}']],
      description: 'Add USDC and DAI Morpho deposits and Maple deposit to the PCV Guardian'
    },
    /// oracle pass through setting Volt System Oracle
    {
      target: 'oraclePassThrough',
      values: '0',
      method: 'updateScalingPriceOracle(address)',
      arguments: ['{voltSystemOracle348Bips}'],
      description: 'Point Oracle Pass Through to new oracle address'
    },
    {
      target: 'core',
      values: '0',
      method: 'grantPCVController(address)',
      arguments: ['{timelockController}'],
      description: 'Grant PCV Controller Role to timelock controller'
    },
    {
      target: 'maplePCVDeposit',
      values: '0',
      method: 'deposit()',
      arguments: [],
      description: 'Deposit PCV into Maple'
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
   4. deploy volt system oracle
  
  Governance Steps:
  1. Grant Morpho PCV Router PCV Controller Role
  2. Revoke PCV Controller Role from Compound PCV Router
  3. Remove Compound DAI Deposit from ERC20Allocator
  4. Remove Compound USDC Deposit from ERC20Allocator
  5. Add Morpho DAI Deposit to ERC20Allocator
  6. Add Morpho USDC Deposit to ERC20Allocator
  7. Add USDC and DAI Morpho deposits as well as Maple PCV deposit to the PCV Guardian
  8. Point Oracle Pass Through to new oracle address
  9. Grant PCV Controller to timelock
  10. Deposit funds in Maple PCV Deposit
  11. pause dai compound pcv deposit
  12. pause usdc compound pcv deposit
  `
};

export default vip_14;

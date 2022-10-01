import { ProposalDescription } from '@custom-types/types';

const vip_14: ProposalDescription = {
  title: 'VIP-14: COMP Sell Only PSM',
  commands: [
    {
      target: 'compPSM',
      values: '0',
      method: 'pauseMint()',
      arguments: [],
      description: 'Pause sale of COMP to this PSM'
    },
    {
      target: 'core',
      values: '0',
      method: 'grantPCVController(address)',
      arguments: ['{erc20Skimmer}'],
      description: 'Grant COMP Skimmer ERC20Allocator Role'
    },
    {
      target: 'erc20Skimmer',
      values: '0',
      method: 'addDeposit(address)',
      arguments: ['{daiCompoundPCVDeposit}'],
      description: 'Add Compound DAI PCV Deposit to COMP Skimmer'
    },
    {
      target: 'erc20Skimmer',
      values: '0',
      method: 'addDeposit(address)',
      arguments: ['{usdcCompoundPCVDeposit}'],
      description: 'Add Compound USDC PCV Deposit to COMP Skimmer'
    }
  ],
  description: 'VIP-14: COMP Sell Only PSM'
};

export default vip_14;

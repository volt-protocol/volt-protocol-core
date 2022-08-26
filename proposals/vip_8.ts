import { ProposalDescription } from '@custom-types/types';

const vip_8: ProposalDescription = {
  title: 'VIP-8: Enable DAI PSM',
  commands: [
    {
      target: 'feiPriceBoundPSM',
      values: '0',
      method: 'pauseRedeem()',
      arguments: [],
      description: 'Pause redemptions on the FEI PSM'
    },
    {
      target: 'fei',
      values: '0',
      method: 'approve(address,uint256)',
      arguments: ['{makerRouter}', '2400000000000000000000000'],
      description: 'Timelock approves router to spend FEI'
    },
    {
      target: 'makerRouter',
      values: '0',
      method: 'swapAllFeiForDai(address)',
      arguments: ['{daiPriceBoundPSM}'],
      description: 'Swaps FEI for DAI proceeds sent to DAI PSM'
    },
    {
      target: 'fei',
      values: '0',
      method: 'approve(address,uint256)',
      arguments: ['{makerRouter}', 0],
      description: 'Timelock revokes router approval to spend FEI'
    }
  ],
  description: 'Enables the DAI PSM on Mainnet'
};

export default vip_8;

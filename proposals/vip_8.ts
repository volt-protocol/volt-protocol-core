import { ProposalDescription } from '@custom-types/types';
import { ethers } from 'hardhat';

const vip_8: ProposalDescription = {
  title: 'VIP-8: Enable DAI PSM',
  commands: [
    {
      target: 'fei',
      values: '0',
      method: 'approve(address,uint)',
      arguments: ['{makerRouter}', ethers.constants.MaxUint256],
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
      method: 'approve(address,uint)',
      arguments: ['{makerRouter}', 0],
      description: 'Timelock revokes router approval to spend FEI'
    }
  ],
  description: 'Enables the DAI PSM on Mainnet'
};

export default vip_8;

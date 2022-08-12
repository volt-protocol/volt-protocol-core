import { ProposalDescription } from '@custom-types/types';

const vip_6: ProposalDescription = {
  title: `VIP-6: Set Mint and Redeem Fees to 0 on Arbitrum`,
  commands: [
    {
      target: 'arbitrumDAIPSM',
      values: '0',
      method: 'setMintFee(uint256)',
      arguments: ['0'],
      description: 'Set mint fee to 0 basis points on DAI PSM'
    },
    {
      target: 'arbitrumDAIPSM',
      values: '0',
      method: 'setRedeemFee(uint256)',
      arguments: ['0'],
      description: 'Set redeem fee to 0 basis points on DAI PSM'
    },
    {
      target: 'arbitrumUSDCPSM',
      values: '0',
      method: 'setMintFee(uint256)',
      arguments: ['0'],
      description: 'Set mint fee to 0 basis points on USDC PSM'
    },
    {
      target: 'arbitrumUSDCPSM',
      values: '0',
      method: 'setRedeemFee(uint256)',
      arguments: ['0'],
      description: 'Set redeem fee to 0 basis points on USDC PSM'
    }
  ],
  description: 'Set Mint Fees to 0 on Arbitrum'
};

export default vip_6;

import { ProposalDescription } from '@custom-types/types';

const vip_3: ProposalDescription = {
  title: 'VIP-3: Repay Fei Loan',
  commands: [
    {
      target: 'fei',
      values: '0',
      method: 'transfer(address,uint256)',
      arguments: ['{otcEscrowRepayment}', '10170000000000000000000000'],
      description: 'Transfer Fei to Otc Escrow'
    }
  ],
  description: `Transfer Fei to Otc Escrow Contract to repay loan`
};

export default vip_3;

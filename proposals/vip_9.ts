import { ProposalDescription } from '@custom-types/types';

const vip_9: ProposalDescription = {
  title: 'VIP-9: Whitelist Compound PCV Deposits in PCV Guardian',
  commands: [
    {
      target: 'pcvGuardian',
      values: '0',
      method: 'addWhitelistAddresses(address[])',
      arguments: [['{daiCompoundPCVDeposit}', '{feiCompoundPCVDeposit}', '{usdcCompoundPCVDeposit}']],
      description: 'Add DAI, FEI, and USDC Compound PCV Deposit to PCV Guardian'
    }
  ],
  description: 'Add DAI, FEI, and USDC Compound PCV Deposit to PCV Guardian'
};

export default vip_9;

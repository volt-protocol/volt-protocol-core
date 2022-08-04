import { ProposalDescription } from '@custom-types/types';

const vip_6: ProposalDescription = {
  title: 'VIP-6: PSM Restructuring',
  commands: [
    {
      target: 'feiPriceBoundPSM',
      values: '0',
      method: 'pauseMint()',
      arguments: [],
      description: 'Pause Minting on the FEI PSM'
    },
    {
      target: 'pcvGuardian',
      values: '0',
      method: 'withdrawAllERC20ToSafeAddress(address, address)',
      arguments: ['{feiPriceBoundPSM}', '{volt}'],
      description: 'Remove all VOLT from FEI PSM'
    },
    {
      target: 'pcvGuardian',
      values: '0',
      method: 'addWhitelistAddress(address',
      arguments: ['{daiPriceBoundPSM}'], // todo add to list of addresses
      description: 'Add DAI PSM to whitelisted addresses on PCV GuardianM'
    }
  ],
  description: 'Pauses minting on FEI PSM, remove VOLT liquidity from FEI PSM, adds DAI PSM to PCVGuardian whitelist'
};

export default vip_6;

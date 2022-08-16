import { ProposalDescription } from '@custom-types/types';

const vip_7: ProposalDescription = {
  title: 'VIP-7: PSM Restructuring',
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
      method: 'addWhitelistAddress(address)',
      arguments: ['{daiPriceBoundPSM}'], // todo add to list of addresses
      description: 'Add DAI PSM to whitelisted addresses on PCV Guardian'
    },
    {
      target: 'usdcPriceBoundPSM',
      values: '0',
      method: 'unpauseRedeem()',
      arguments: [],
      description: 'Unpause redemptions for USDC PSM'
    }
  ],
  description:
    'Pauses minting on FEI PSM, remove VOLT liquidity from FEI PSM, adds DAI PSM to PCVGuardian whitelist, unpause redemptions on the USDC PSM'
};

export default vip_7;

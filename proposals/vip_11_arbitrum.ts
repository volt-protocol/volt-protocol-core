import { ProposalDescription } from '@custom-types/types';

const vip_11: ProposalDescription = {
  title: 'VIP-11: Arbitrum Rate Update',
  commands: [
    {
      target: 'arbitrumOraclePassThrough',
      values: '0',
      method: 'updateScalingPriceOracle(address)',
      arguments: ['{arbitrumVoltSystemOracle}'],
      description: 'Set Volt System Oracle on Oracle Pass Through'
    }
  ],
  description: 'Upgrade volt oracle from 60 to 144 basis points annually'
};

export default vip_11;

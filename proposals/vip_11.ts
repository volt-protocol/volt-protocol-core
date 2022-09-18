import { ProposalDescription } from '@custom-types/types';

const vip_11: ProposalDescription = {
  title: 'VIP-11: Mainnet Rate Update',
  commands: [
    {
      target: 'oraclePassThrough',
      values: '0',
      method: 'updateScalingPriceOracle(address)',
      arguments: ['{voltSystemOracle}'],
      description: 'Set Volt System Oracle on Oracle Pass Through'
    }
  ],
  description: 'Upgrade volt oracle from 60 to 144 basis points annually'
};

export default vip_11;

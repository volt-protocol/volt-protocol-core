import { ProposalDescription } from '@custom-types/types';

const vip_2: ProposalDescription = {
  title: 'VIP-2: New Oracle Upgrade on Arbitrum',
  commands: [
    {
      target: 'arbitrumDAIPSM',
      values: '0',
      method: 'setOracle(address)',
      arguments: ['{oraclePassThroughArbitrum}'],
      description: 'Set oracle pass through on DAI PSM'
    },
    {
      target: 'arbitrumUSDCPSM',
      values: '0',
      method: 'setOracle(address)',
      arguments: ['{oraclePassThroughArbitrum}'],
      description: 'Set oracle pass through on USDC PSM'
    },
    {
      target: 'arbitrumCore',
      values: '0',
      method: 'grantGuardian(address)',
      arguments: ['{pcvGuardEOA1}'],
      description: 'Grant Guardian Roles on L2'
    },
    {
      target: 'arbitrumCore',
      values: '0',
      method: 'grantGuardian(address)',
      arguments: ['{pcvGuardEOA2}'],
      description: 'Grant Guardian Roles on L2'
    },
    {
      target: 'arbitrumOptimisticTimelock',
      values: '0',
      method: 'revokeRole(bytes32,address)',
      arguments: ['0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1', '{pcvGuardRevoked1}'],
      description: 'Revoke proposer role from revoked EOA'
    },
    {
      target: 'arbitrumOptimisticTimelock',
      values: '0',
      method: 'grantRole(bytes32,address)',
      arguments: ['0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1', '{pcvGuardEOA1}'],
      description: 'Grant proposer role to EOA 1'
    }
  ],
  description: `
  Point both DAI and USDC PSM to the new OraclePassThrough contract, 
  grant guardian role to EOAs, revoke old eoa proposer ability, grant new eoa proposer ability
  `
};

export default vip_2;

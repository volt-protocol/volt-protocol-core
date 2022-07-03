import { ProposalDescription } from '@custom-types/types';

const vip_2: ProposalDescription = {
  title: 'VIP-2: New Oracle Upgrade',
  commands: [
    {
      target: 'usdcPriceBoundPSM',
      values: '0',
      method: 'setOracle(address)',
      arguments: ['{oraclePassThrough}'],
      description: 'Set oracle pass through on USDC PSM'
    },
    {
      target: 'feiPriceBoundPSM',
      values: '0',
      method: 'setOracle(address)',
      arguments: ['{oraclePassThrough}'],
      description: 'Set oracle pass through on FEI PSM'
    },
    {
      target: 'core',
      values: '0',
      method: 'grantGuardian(address)',
      arguments: ['{pcvGuardEOA3}'],
      description: 'Grant Guardian Roles to EOA 3 on mainnet'
    },
    {
      target: 'optimisticTimelock',
      values: '0',
      method: 'grantRole(bytes32,address)',
      arguments: ['0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1', '{pcvGuardEOA1}'],
      description: 'Grant proposer role to EOA 1'
    },
    {
      target: 'optimisticTimelock',
      values: '0',
      method: 'revokeRole(bytes32,address)',
      arguments: ['0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1', '{pcvGuardRevoked1}'],
      description: 'Revoke proposer role from revoked EOA'
    }
  ],
  description: `Point both FEI and USDC PSM to the new OraclePassThrough contract, grant EOA 3 guardian role`
};

export default vip_2;

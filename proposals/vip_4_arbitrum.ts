import { ProposalDescription } from '@custom-types/types';

const vip_4: ProposalDescription = {
  title: 'VIP-4: Role Cleanup',
  commands: [
    /// Role revocations
    {
      target: 'arbitrumPCVGuardAdmin',
      values: '0',
      method: 'revokePCVGuardRole(address)',
      arguments: ['{pcvGuardRevoked1}'],
      description: 'Revoke PCV Guard role from revoked EOA1 by calling PCVGuardAdmin'
    },
    {
      target: 'arbitrumCore',
      values: '0',
      method: 'revokeGuardian(address)',
      arguments: ['{pcvGuardEOA1}'],
      description: 'Revoke EOA1 as a guardian'
    },
    {
      target: 'arbitrumCore',
      values: '0',
      method: 'revokePCVController(address)',
      arguments: ['{arbitrumOptimisticTimelock}'],
      description: `Revoke Deprecated Timelock's PCV Controller role`
    },
    /// Role additions
    {
      target: 'arbitrumPCVGuardAdmin',
      values: '0',
      method: 'grantPCVGuardRole(address)',
      arguments: ['{pcvGuardEOA1}'],
      description: 'Grant EOA 1 PCV Guard Role'
    },
    {
      target: 'arbitrumPCVGuardAdmin',
      values: '0',
      method: 'grantPCVGuardRole(address)',
      arguments: ['{pcvGuardEOA2}'],
      description: 'Grant EOA 2 PCV Guard Role'
    },
    {
      target: 'arbitrumPCVGuardAdmin',
      values: '0',
      method: 'grantPCVGuardRole(address)',
      arguments: ['{pcvGuardEOA3}'],
      description: 'Grant EOA 3 PCV Guard Role'
    }
  ],
  description: `Revoke unused roles, add new roles`
};

export default vip_4;

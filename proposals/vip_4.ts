import { ProposalDescription } from '@custom-types/types';

const vip_4: ProposalDescription = {
  title: 'VIP-4: Role Cleanup',
  commands: [
    /// Role revocations
    {
      target: 'pcvGuardAdmin',
      values: '0',
      method: 'revokePCVGuardRole(address)',
      arguments: ['{pcvGuardRevoked1}'],
      description: 'Revoke PCV Guard role from revoked EOA1 by calling PCVGuardAdmin'
    },
    {
      target: 'core',
      values: '0',
      method: 'revokeGuardian(address)',
      arguments: ['{pcvGuardEOA1}'],
      description: 'Revoke guardian from new EOA1'
    },
    {
      target: 'core',
      values: '0',
      method: 'revokeMinter(address)',
      arguments: ['{globalRateLimitedMinter}'],
      description: 'Revoke minter from global rate limited minter'
    },
    {
      target: 'core',
      values: '0',
      method: 'revokePCVController(address)',
      arguments: ['{nonCustodialFusePSM}'],
      description: 'Revoke PCV Controller from non custodial psm'
    },
    {
      target: 'core',
      values: '0',
      method: 'revokeGuardian(address)',
      arguments: ['{protocolMultisig}'],
      description: 'Revoke Guardian Role from Multisig'
    },
    /// Role additions
    {
      target: 'pcvGuardAdmin',
      values: '0',
      method: 'grantPCVGuardRole(address)',
      arguments: ['{pcvGuardEOA1}'],
      description: 'Grant EOA1 PCV Guard role'
    },
    {
      target: 'pcvGuardAdmin',
      values: '0',
      method: 'grantPCVGuardRole(address)',
      arguments: ['{pcvGuardEOA2}'],
      description: 'Grant EOA2 PCV Guard role'
    },
    {
      target: 'pcvGuardAdmin',
      values: '0',
      method: 'grantPCVGuardRole(address)',
      arguments: ['{pcvGuardEOA3}'],
      description: 'Grant EOA3 PCV Guard role'
    }
  ],
  description: `Revoke unused roles, add new roles`
};

export default vip_4;

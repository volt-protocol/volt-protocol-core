import { ProposalDescription } from '@custom-types/types';

const vip_1: ProposalDescription = {
  title: 'VIP-1: Grant Param Admin Role',
  commands: [
    {
      target: 'core',
      values: '0',
      method: 'createRole(bytes32,bytes32)',
      arguments: [
        '0xf0b50f04623eeaacfa1f202e062a3001c925a35c6b75d6903e67b43f44bbf152', // PARAMETER_ADMIN
        '0x2172861495e7b85edac73e3cd5fbb42dd675baadf627720e687bcfdaca025096' // ROLE_ADMIN
      ],
      description: 'Transfer PARAMETER_ADMIN role admin to ROLE_ADMIN'
    },
    {
      target: 'core',
      values: '0',
      method: 'createRole(bytes32,bytes32)',
      arguments: [
        '0xdc81827f5af6c7965785d62c38ca3481ccf540d7f561cac825518e49d6161c95', // RATE_LIMITED_MINTER_ADMIN
        '0x2172861495e7b85edac73e3cd5fbb42dd675baadf627720e687bcfdaca025096' // ROLE_ADMIN
      ],
      description: 'Transfer RATE_LIMITED_MINTER_ADMIN role admin to ROLE_ADMIN'
    },
    {
      target: 'core',
      values: '0',
      method: 'createRole(bytes32,bytes32)',
      arguments: [
        '0xdc81827f5af6c7965785d62c38ca3481ccf540d7f561cac825518e49d6160000', // RATE_LIMITED_MINTER_ADMIN
        '0x2172861495e7b85edac73e3cd5fbb42dd675baadf627720e687bcfdaca025096' // ROLE_ADMIN
      ],
      description: 'Transfer RATE_LIMITED_MINTER_ADMIN role admin to ROLE_ADMIN'
    },
    {
      target: 'core',
      values: '0',
      method: 'isGovernor(address)',
      arguments: ['{core}'],
      description: 'Check if core is governor'
    }
  ],
  description: `Grant the Timelock Governor Role`,
  salt: '0x73616c7400000000000000000000000000000000000000000000000000000000',
  predecessor: '0x70726f63656564696e672070726f706f73616c00000000000000000000000000',
  delay: 600
};

export default vip_1;

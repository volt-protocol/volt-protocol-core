import { ProposalCategory, ProposalsConfigMap } from '@custom-types/types';

// import fip_xx_proposal from '@proposals/description/fip_xx';
import volt_deploy from '@proposals/description/volt_deploy';

const proposals: ProposalsConfigMap = {
  /*
  fip_xx: {
    deploy: false,
    proposalId: undefined,
    affectedContractSignoff: ['reptbRedeemer', 'fei', 'pegExchanger'],
    deprecatedContractSignoff: [],
    category: ProposalCategory.DAO,
    totalValue: 0,
    proposal: fip_xx_proposal
  }
  */
  volt_deploy: {
    deploy: true,
    proposalId: undefined,
    affectedContractSignoff: ['vcon', 'volt', 'core', 'voltDAO', 'timelock'],
    deprecatedContractSignoff: [],
    category: ProposalCategory.DAO,
    totalValue: 0,
    proposal: volt_deploy
  }
};

export default proposals;

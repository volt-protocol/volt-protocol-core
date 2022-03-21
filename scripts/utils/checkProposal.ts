import { getAllContracts, getAllContractAddresses } from '@test/integration/setup/loadContracts';
import { NamedContracts, UpgradeFuncs } from '@custom-types/types';
import proposals from '@test/integration/proposals_config';

import * as dotenv from 'dotenv';
import { execProposal } from './exec';

dotenv.config();

// Multisig
const voterAddress = '0xB8f482539F2d3Ae2C9ea6076894df36D1f632775';
const proposalName = process.env.DEPLOY_FILE;

if (!proposalName) {
  throw new Error('DEPLOY_FILE env variable not set');
}

/**
 * Take in a hardhat proposal object and output the proposal calldatas
 * See `proposals/utils/getProposalCalldata.js` on how to construct the proposal calldata
 */
async function checkProposal(proposalName: string) {
  // Get the upgrade setup, run and teardown scripts
  console.log('checkProposal 0');
  const proposalFuncs: UpgradeFuncs = await import(`@proposals/dao/${proposalName}`);

  console.log('checkProposal 1');

  const contracts = (await getAllContracts()) as unknown as NamedContracts;
  console.log('checkProposal 2');

  const contractAddresses = getAllContractAddresses();
  console.log('checkProposal 3');

  if (process.env.DO_SETUP) {
    console.log('checkProposal 4');
    console.log('Setup');
    await proposalFuncs.setup(
      contractAddresses,
      contracts as unknown as NamedContracts,
      contracts as unknown as NamedContracts,
      true
    );
  }

  console.log('checkProposal 5');
  const { feiDAO } = contracts;
  console.log('checkProposal 6');

  const proposalNo = proposals[proposalName].proposalId;
  console.log('checkProposal 7');

  await execProposal(voterAddress, feiDAO.address, proposals[proposalName].totalValue, proposalNo);
  console.log('checkProposal 8');

  console.log('Teardown');
  await proposalFuncs.teardown(
    contractAddresses,
    contracts as unknown as NamedContracts,
    contracts as unknown as NamedContracts,
    true
  );

  console.log('Validate');
  await proposalFuncs.validate(
    contractAddresses,
    contracts as unknown as NamedContracts,
    contracts as unknown as NamedContracts,
    true
  );
}

checkProposal(proposalName)
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

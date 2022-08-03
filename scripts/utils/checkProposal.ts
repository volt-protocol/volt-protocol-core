import { getAllContracts, getAllContractAddresses } from './loadContracts';
import { NamedAddresses, NamedContracts, UpgradeFuncs, namedContractsToNamedAddresses } from '@custom-types/types';
import { simulateOAProposal, simulateOAProposalArbitrum } from '../simulation/simulateTimelockProposal';
import { MainnetContracts, ProposalDescription } from '@custom-types/types';
import { ethers } from 'hardhat';
import * as dotenv from 'dotenv';

dotenv.config();

const doSetup = process.env.DO_SETUP;
const doDeploy = process.env.DO_DEPLOY;
const isArbitrumVip = process.env.ENABLE_ARBITRUM_FORKING;
const proposalName = process.env.DEPLOY_FILE + (isArbitrumVip ? '_arbitrum' : '');

if (!proposalName) {
  throw new Error('DEPLOY_FILE env variable not set');
}

/**
 * Take in a hardhat proposal object and output the proposal calldatas
 * See `proposals/utils/getProposalCalldata.js` on how to construct the proposal calldata
 */
async function checkProposal(proposalName: string, doSetup?: string) {
  // Get the upgrade setup, run and teardown scripts
  const proposalFuncs: UpgradeFuncs = await import(`@proposals/dao/${proposalName}`);

  let contracts = (await getAllContracts()) as unknown as NamedContracts;

  let contractAddresses = getAllContractAddresses();

  const proposalInfo = (await import(`@proposals/${proposalName}`)).default as ProposalDescription;
  const deployer = (await ethers.getSigners())[0];

  if (doDeploy) {
    console.log('Deploy');
    const deployed = await proposalFuncs.deploy(deployer.address, contractAddresses, true);
    contracts = {
      ...contracts,
      ...deployed
    };
    contractAddresses = {
      ...contractAddresses,
      ...namedContractsToNamedAddresses(deployed)
    };
  }

  if (doSetup) {
    console.log('Setup');
    await proposalFuncs.setup(
      contractAddresses,
      contracts as unknown as NamedContracts,
      contracts as unknown as NamedContracts,
      true
    );
  }

  console.log(`Starting Simulation of OA proposal...`);
  if (isArbitrumVip) {
    await simulateOAProposalArbitrum(proposalInfo, contracts as unknown as MainnetContracts, contractAddresses, true);
    console.log(`Successfully Simulated OA proposal on arbitrum`);
  } else {
    await simulateOAProposal(proposalInfo, contracts as unknown as MainnetContracts, contractAddresses, true);
    console.log(`Successfully Simulated OA proposal on mainnet`);
  }

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

checkProposal(proposalName, doSetup)
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

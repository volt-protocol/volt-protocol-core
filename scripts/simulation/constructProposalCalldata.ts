import { ethers } from 'ethers';
import { Interface } from '@ethersproject/abi';
import { utils } from 'ethers';
import { getAllContractAddresses, getAllContracts } from '@scripts/utils/loadContracts';
import { ProposalDescription, ExtendedAlphaProposal } from '@custom-types/types';
import constructProposal from './constructProposal';

/**
 * Take in a hardhat proposal object and output the proposal calldatas
 * See `proposals/utils/getProposalCalldata.js` on how to construct the proposal calldata
 */
export async function constructProposalCalldata(proposalName: string): Promise<string> {
  const proposalInfo = (await import(`@proposals/${proposalName}`)).default as ProposalDescription;

  const contracts = await getAllContracts();
  const contractAddresses = await getAllContractAddresses();
  const proposal = (await constructProposal(proposalInfo, contracts, contractAddresses)) as ExtendedAlphaProposal;

  return getTimelockCalldata(proposal, proposalInfo);
}

function getTimelockCalldata(proposal: ExtendedAlphaProposal, proposalInfo: ProposalDescription): string {
  const proposeFuncFrag = new Interface([
    'function scheduleBatch(address[] calldata targets,uint256[] calldata values,bytes[] calldata data,bytes32 predecessor,bytes32 salt,uint256 delay) public',
    'function executeBatch(address[] calldata targets,uint256[] calldata values,bytes[] calldata data,bytes32 predecessor,bytes32 salt) public'
  ]);

  const combinedCalldatas = [];
  for (let i = 0; i < proposal.targets.length; i++) {
    const sighash = utils.id(proposal.signatures[i]).slice(0, 10);
    combinedCalldatas.push(`${sighash}${proposal.calldatas[i].slice(2)}`);
  }

  const abiEncodedString = ethers.utils.defaultAbiCoder.encode(['string'], [proposalInfo.commands[0].description]);
  const salt = ethers.utils.keccak256(abiEncodedString);
  console.log(`salt: ${salt}`);

  const predecessor = ethers.constants.HashZero;

  const calldata = proposeFuncFrag.encodeFunctionData('scheduleBatch', [
    proposal.targets,
    proposal.values,
    combinedCalldatas,
    predecessor,
    salt,
    86400
  ]);

  const executeCalldata = proposeFuncFrag.encodeFunctionData('executeBatch', [
    proposal.targets,
    proposal.values,
    combinedCalldatas,
    predecessor,
    salt
  ]);

  return `Calldata: ${calldata}\nExecute Calldata: ${executeCalldata}`;
}

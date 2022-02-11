import constructProposal from './constructProposal';
import { BigNumber } from 'ethers';
import { Interface } from '@ethersproject/abi';
import { utils } from 'ethers';
import { getAllContractAddresses, getAllContracts } from '@test/integration/setup/loadContracts';

type ExtendedAlphaProposal = {
  targets: string[];
  values: BigNumber[];
  signatures: string[];
  calldatas: string[];
  description: string;
};

/**
 * Take in a hardhat proposal object and output the proposal calldatas
 * See `proposals/utils/getProposalCalldata.js` on how to construct the proposal calldata
 */
export async function constructProposalCalldata(proposalName: string): Promise<string> {
  console.log('constructProposalCalldata 0');
  const proposalInfo = await import(`@proposals/description/${proposalName}`);
  console.log('constructProposalCalldata 1');

  const contracts = await getAllContracts();
  console.log('constructProposalCalldata 2');
  const contractAddresses = await getAllContractAddresses();
  console.log('constructProposalCalldata 3');

  const proposal = (await constructProposal(
    proposalInfo.default,
    contracts,
    contractAddresses
  )) as ExtendedAlphaProposal;
  console.log('constructProposalCalldata 4');

  const proposeFuncFrag = new Interface([
    'function propose(address[] memory targets,uint256[] memory values,bytes[] memory calldatas,string memory description) public returns (uint256)'
  ]);
  console.log('constructProposalCalldata 5');

  const combinedCalldatas = [];
  for (let i = 0; i < proposal.targets.length; i++) {
    const sighash = utils.id(proposal.signatures[i]).slice(0, 10);
    combinedCalldatas.push(`${sighash}${proposal.calldatas[i].slice(2)}`);
  }
  console.log('constructProposalCalldata 6');

  const calldata = proposeFuncFrag.encodeFunctionData('propose', [
    proposal.targets,
    proposal.values,
    combinedCalldatas,
    proposal.description
  ]);

  console.log('constructProposalCalldata 7');

  return calldata;
}

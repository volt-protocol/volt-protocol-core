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
  predecessor: string;
  salt: string;
  delay: number;
};

/**
 * Take in a hardhat proposal object and output the proposal calldatas
 * See `proposals/utils/getProposalCalldata.js` on how to construct the proposal calldata
 */
export async function constructProposalCalldata(proposalName: string): Promise<string> {
  const proposalInfo = await import(`@proposals/description/${proposalName}`);

  const contracts = await getAllContracts();
  const contractAddresses = await getAllContractAddresses();

  const proposal = (await constructProposal(
    proposalInfo.default,
    contracts,
    contractAddresses
  )) as ExtendedAlphaProposal;

  const proposeFuncFrag = new Interface([
    'function scheduleBatch(address[] calldata targets,uint256[] calldata values,bytes[] calldata datas,bytes32 predecessor,bytes32 salt,uint256 delay'
  ]);

  const combinedCalldatas = [];
  for (let i = 0; i < proposal.targets.length; i++) {
    const sighash = utils.id(proposal.signatures[i]).slice(0, 10);
    combinedCalldatas.push(`${sighash}${proposal.calldatas[i].slice(2)}`);
  }

  const calldata = proposeFuncFrag.encodeFunctionData('scheduleBatch', [
    proposal.targets,
    proposal.values,
    combinedCalldatas,
    proposal.predecessor,
    proposal.salt,
    proposal.delay
  ]);

  return calldata;
}

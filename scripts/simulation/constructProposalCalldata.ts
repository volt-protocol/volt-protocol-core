import { ethers } from 'ethers';
import { Interface } from '@ethersproject/abi';
import { utils } from 'ethers';
import { getAllContractAddresses, getAllContracts } from '@scripts/utils/loadContracts';
import format from 'string-template';
import { NamedAddresses } from '@custom-types/types';

/**
 * Take in a hardhat proposal object and output the proposal calldatas
 * See `proposals/utils/getProposalCalldata.js` on how to construct the proposal calldata
 */
export async function constructProposalCalldata(proposalName: string): Promise<string> {
  const proposalInfo = (await import(`@proposals/${proposalName}`)).default;

  const contracts = await getAllContracts();
  const contractAddresses = await getAllContractAddresses();

  const targets = [];
  const values = [];
  const calldatas = [];

  for (const command of proposalInfo.commands) {
    const ethersContract = contracts[command.target];
    const args = replaceArgs(command.arguments, contractAddresses);

    targets.push(ethersContract.address);
    values.push(command.values);
    calldatas.push(args);
  }

  if (targets.length !== values.length || calldatas.length !== values.length) {
    throw new Error('Invalid proposal');
  }

  const proposeFuncFrag = new Interface([
    'function scheduleBatch(address[] calldata targets,uint256[] calldata values,bytes[] calldata datas,bytes32 predecessor,bytes32 salt,uint256 delay) public'
  ]);

  const combinedCalldatas = [];
  for (let i = 0; i < targets.length; i++) {
    const args = calldatas[i];
    // check regex if there are arguments in the function signature
    const functionArgTypes = proposalInfo.commands[i].method.match(/\(([^)]+)\)/);
    const sighash = utils.id(proposalInfo.commands[i].method).slice(0, 10);
    if (functionArgTypes || (Array.isArray(functionArgTypes) && functionArgTypes.length > 0)) {
      const types = functionArgTypes[1].split(',');
      // remove first 2 bytes 0x from abi encoded data as sighash already has 0x prefix
      combinedCalldatas.push(`${sighash}${ethers.utils.defaultAbiCoder.encode(types, args).slice(2)}`);
    } else {
      /// call a function without any arguments
      combinedCalldatas.push(`${sighash}00000000000000000000000000000000000000000000000000000000`);
    }
  }

  const calldata = proposeFuncFrag.encodeFunctionData('scheduleBatch', [
    targets,
    values,
    combinedCalldatas,
    proposalInfo.predecessor,
    proposalInfo.salt,
    proposalInfo.delay
  ]);

  return calldata;
}

// Recursively interpolate strings in the argument array
export function replaceArgs(args: any[], contractNames: NamedAddresses): any[] {
  const result = [];
  for (let i = 0; i < args.length; i++) {
    const element = args[i];
    if (typeof element === typeof '') {
      const formatted = format(element, contractNames);
      result.push(formatted);
    } else if (typeof element === typeof []) {
      result.push(replaceArgs(element, contractNames));
    } else {
      result.push(element);
    }
  }
  return result;
}

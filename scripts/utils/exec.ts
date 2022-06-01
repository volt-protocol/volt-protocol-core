import hre, { ethers } from 'hardhat';
import { time, getImpersonatedSigner } from '@test/helpers';

import * as dotenv from 'dotenv';

dotenv.config();

const toBN = ethers.BigNumber.from;

// This script fully executes a timelock proposal with pre-supplied calldata
export async function execProposal(
  voterAddress: string,
  governorAlphaAddress: string,
  totalValue: number,
  proposalNo: string
): Promise<void> {
  const governor = await ethers.getContractAt('FeiDAO', governorAlphaAddress);
  const signer = await getImpersonatedSigner(voterAddress);

  console.log(`Proposal Number: ${proposalNo}`);

  let proposal = await governor.proposals(proposalNo);
  const { startBlock } = proposal;

  // Advance to vote start
  if (toBN(await time.latestBlock()).lt(toBN(startBlock))) {
    console.log(`Advancing To: ${startBlock}`);
    await time.advanceBlockTo(startBlock);
  } else {
    console.log('Vote already began');
  }

  proposal = await governor.proposals(proposalNo);
  const { endBlock } = proposal;

  // Advance to after vote completes and queue the transaction
  if (toBN(await time.latestBlock()).lt(toBN(endBlock))) {
    await governor.connect(signer).castVote(proposalNo, 1);
    console.log('Casted vote');

    console.log(`Advancing To: ${endBlock}`);
    await time.advanceBlockTo(endBlock);

    console.log('Queuing');
    await governor['queue(uint256)'](proposalNo);
  } else {
    console.log('Already queued');
  }

  // Increase beyond the timelock delay
  console.log('Increasing Time');
  await time.increase(200000); // ~2 days in seconds

  console.log('Executing');
  await governor['execute(uint256)'](proposalNo, { value: totalValue });
  console.log('Success');
}

import MainnetAddresses from '../../protocol-configuration/mainnetAddresses';
import { ethers } from 'hardhat';

// Run the deployment for DEPLOY_FILE
async function main() {
  const isArbitrumVip = process.env.ENABLE_ARBITRUM_FORKING;
  const proposalName = process.env.DEPLOY_FILE + (isArbitrumVip ? '_arbitrum' : '');

  if (!proposalName) {
    throw new Error('DEPLOY_FILE env variable not set');
  }

  const deployAddress = (await ethers.getSigners())[0].address;

  const mainnetAddresses = {};
  Object.keys(MainnetAddresses).map((key) => {
    mainnetAddresses[key] = MainnetAddresses[key].address;
    return true;
  });

  const { deploy } = await import(`@proposals/dao/${proposalName}`);

  await deploy(deployAddress, mainnetAddresses, true);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

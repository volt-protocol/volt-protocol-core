import hre, { ethers } from 'hardhat';

import config from './config';
const { NON_CUSTODIAL_PSM, FEI_DAI_PSM, VOLT, FEI, DAI } = config;

async function deploy() {
  const PSMRouter = await ethers.getContractFactory('PSMRouter');
  const psmRouter = await PSMRouter.deploy(NON_CUSTODIAL_PSM, FEI_DAI_PSM, VOLT, FEI, DAI);
  await psmRouter.deployed();

  console.log('\n ~~~~~ Deployed PSM Router Successfully ~~~~~ \n');
  console.log(`PSMRouter:        ${psmRouter.address}`);

  await hre.run('verify:verify', {
    address: psmRouter.address,
    constructorArguments: [NON_CUSTODIAL_PSM, FEI_DAI_PSM, VOLT, FEI, DAI]
  });

  return;
}

deploy()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

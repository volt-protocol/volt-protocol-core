import hre, { ethers } from 'hardhat';
import config from './config';

const deploy = async () => {
  const core = config.CORE;

  const CTOKEN = process.env.CTOKEN;

  if (!CTOKEN) {
    throw new Error('CTOKEN environment variable contract address is not set');
  }

  if (!core) {
    throw new Error('An environment variable contract address is not set');
  }

  const erc20CompoundPCVDepositFactory = await ethers.getContractFactory('ERC20CompoundPCVDeposit');
  const erc20CompoundPCVDeposit = await erc20CompoundPCVDepositFactory.deploy(core, CTOKEN);
  await erc20CompoundPCVDeposit.deployed();

  console.log('ERC20CompoundPCVDeposit deployed to: ', erc20CompoundPCVDeposit.address);

  await hre.run('verify:verify', {
    address: erc20CompoundPCVDeposit.address,
    constructorArguments: [core, CTOKEN]
  });

  return;
};

deploy()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

import hre, { ethers } from 'hardhat';
import config from './config';

async function deploy() {
  const { FEI, VOLT, FEI_DAO_TIMELOCK, VOLT_SWAP_AMOUNT, VOLT_FUSE_PCV_DEPOSIT } = config;

  if (!FEI || !VOLT || !FEI_DAO_TIMELOCK || !VOLT_SWAP_AMOUNT || !VOLT_FUSE_PCV_DEPOSIT) {
    throw new Error('Variable not set');
  }

  const factory = await ethers.getContractFactory('OtcEscrow');
  const otcEscrow = await factory.deploy(
    FEI_DAO_TIMELOCK, // FEI DAO timelock receives the VOLT
    VOLT_FUSE_PCV_DEPOSIT, // VOLT FUSE PCV Deposit is the recipient of the FEI because it won't deposit the VOLT into fuse
    FEI, // transfer FEI from timelock to the VOLT FUSE PCV Deposit
    VOLT, // transfer VOLT to the FEI DAO timelock
    ethers.constants.WeiPerEther.mul(10_170_000), // 10.17m FEI as oracle price is currently $1.017 USD per VOLT
    VOLT_SWAP_AMOUNT // FEI DAO receives 10m VOLT
  );
  await otcEscrow.deployed();

  console.log('OTC deployed to: ', otcEscrow.address);
}

async function verify(otcEscrowAddress: string) {
  const { FEI, VOLT, FEI_DAO_TIMELOCK, VOLT_SWAP_AMOUNT, VOLT_FUSE_PCV_DEPOSIT } = config;

  await hre.run('verify:verify', {
    address: otcEscrowAddress,
    constructorArguments: [
      FEI_DAO_TIMELOCK, // FEI DAO timelock receives the VOLT
      VOLT_FUSE_PCV_DEPOSIT, // VOLT FUSE PCV Deposit is the recipient of the FEI because it won't deposit the VOLT into fuse
      FEI, // transfer FEI from timelock to the VOLT FUSE PCV Deposit
      VOLT, // transfer VOLT to the FEI DAO timelock
      ethers.constants.WeiPerEther.mul(10_170_000), // 10.17m FEI as oracle price is currently $1.017 USD per VOLT
      VOLT_SWAP_AMOUNT // FEI DAO receives 10m VOLT
    ]
  });

  console.log('OTC deployed to: ', otcEscrowAddress);
}

if (process.env.DEPLOY) {
  deploy()
    .then(() => process.exit(0))
    .catch((err) => {
      console.log(err);
      process.exit(1);
    });
} else {
  verify(process.env.OTC_ESCROW_ADDRESS)
    .then(() => process.exit(0))
    .catch((err) => {
      console.log(err);
      process.exit(1);
    });
}

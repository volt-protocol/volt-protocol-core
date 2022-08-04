import hre, { ethers } from 'hardhat';
import NetworksForVerification from '@protocol/networksForVerification';
import { PriceBoundPSM } from '@custom-types/contracts';
import { expect } from 'chai';
import { getAllContractAddresses } from './utils/loadContracts';
import { NamedAddresses } from '@custom-types/types';

const voltFloorPrice = '9000000000000000';
const voltCeilingPrice = '10000000000000000';

const daiReservesThreshold = ethers.utils.parseEther('10000000000');
const mintLimitPerSecond = ethers.utils.parseEther('10000');
const voltPSMBufferCap = ethers.utils.parseEther('10000000');

async function deploy(contractAddresses: NamedAddresses) {
  const priceBoundPSM = await (
    await ethers.getContractFactory('PriceBoundPSM')
  ).deploy(
    voltFloorPrice,
    voltCeilingPrice,
    {
      coreAddress: contractAddresses.core,
      oracleAddress: contractAddresses.voltSystemOracle, // OPT
      backupOracle: ethers.constants.AddressZero,
      decimalsNormalizer: 0,
      doInvert: true /// invert the price so that the Oracle and PSM works correctly
    },
    0, // 0 mint fee
    0, // 0 redeem fee
    daiReservesThreshold,
    mintLimitPerSecond,
    voltPSMBufferCap,
    contractAddresses.dai,
    ethers.constants.AddressZero
  );

  await priceBoundPSM.deployed();

  console.log(`\nDAI PriceBoundPSM deployed to: ${priceBoundPSM.address}`);

  return priceBoundPSM;
}

async function validate(priceBoundPSM: PriceBoundPSM, contractAddresses: NamedAddresses) {
  expect(await priceBoundPSM.doInvert()).to.be.true;
  expect(await priceBoundPSM.oracle()).to.be.equal(contractAddresses.core);
  expect(await priceBoundPSM.backupOracle()).to.be.equal(ethers.constants.AddressZero);

  //  volt
  expect(await priceBoundPSM.underlyingToken()).to.be.equal(contractAddresses.dai);
  expect(await priceBoundPSM.volt()).to.be.equal(contractAddresses.volt);

  //  psm params
  expect(await priceBoundPSM.redeemFeeBasisPoints()).to.be.equal(0);
  expect(await priceBoundPSM.mintFeeBasisPoints()).to.be.equal(0);
  expect(await priceBoundPSM.reservesThreshold()).to.be.equal(daiReservesThreshold);
  expect(await priceBoundPSM.surplusTarget()).to.be.equal(ethers.constants.AddressZero);
  expect(await priceBoundPSM.rateLimitPerSecond()).to.be.equal(mintLimitPerSecond);
  expect(await priceBoundPSM.buffer()).to.be.equal(voltPSMBufferCap);
  expect(await priceBoundPSM.bufferCap()).to.be.equal(voltPSMBufferCap);

  //  price bound params
  expect(await priceBoundPSM.floor()).to.be.equal(voltFloorPrice);
  expect(await priceBoundPSM.ceiling()).to.be.equal(voltCeilingPrice);

  //  balance check
  expect(await priceBoundPSM.balance()).to.be.equal(0);
  expect(await priceBoundPSM.voltBalance()).to.be.equal(0);
}

async function verifyEtherscan(priceBoundPSM: string, contractAddresses: NamedAddresses) {
  const oracleParams = {
    coreAddress: contractAddresses.core,
    oracleAddress: contractAddresses.voltSystemOracle,
    backupOracle: ethers.constants.AddressZero,
    decimalsNormalizer: 0,
    doInvert: true
  };

  await hre.run('verify:verify', {
    address: priceBoundPSM,

    constructorArguments: [
      voltFloorPrice,
      voltCeilingPrice,
      oracleParams,
      0,
      0,
      daiReservesThreshold,
      mintLimitPerSecond,
      voltPSMBufferCap,
      contractAddresses.dai,
      ethers.constants.AddressZero
    ]
  });

  console.log('\nSuccessfully Verified DAI PriceBound PSM on Block Explorer');
}

async function main() {
  const contractAddresses = getAllContractAddresses();

  const priceBoundPSM = await deploy(contractAddresses);

  await validate(priceBoundPSM, contractAddresses);

  if (NetworksForVerification[hre.network.name]) {
    await verifyEtherscan(priceBoundPSM.address, contractAddresses);
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

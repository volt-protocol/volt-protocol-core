import hre, { ethers } from 'hardhat';
import NetworksForVerification from '@protocol/networksForVerification';
import { getAllContractAddresses } from './utils/loadContracts';

async function deploy(volt: string, tokenApprovals) {
  const curveRouter = await (await ethers.getContractFactory('CurveRouter')).deploy(volt, tokenApprovals);

  await curveRouter.deployed();

  console.log(`\nCurve Router deployed to: ${curveRouter.address}`);

  return curveRouter;
}

async function verifyEtherscan(curveRouter: string, volt: string, tokenApprovals) {
  await hre.run('verify:verify', {
    address: curveRouter,
    constructorArguments: [volt, tokenApprovals]
  });

  console.log('\nSuccessfully Verified Timelock on Block Explorer');
}

async function main() {
  const contractAddresses = getAllContractAddresses();

  const tokenApprovals = [
    { token: contractAddresses.volt, contractToApprove: contractAddresses.usdcPriceBoundPSM },
    { token: contractAddresses.usdc, contractToApprove: contractAddresses.usdcPriceBoundPSM },
    { token: contractAddresses.volt, contractToApprove: contractAddresses.feiPriceBoundPSM },
    { token: contractAddresses.fei, contractToApprove: contractAddresses.feiPriceBoundPSM },
    { token: contractAddresses.dai, contractToApprove: contractAddresses.daiUsdcUsdtCurvePool },
    { token: contractAddresses.usdt, contractToApprove: contractAddresses.daiUsdcUsdtCurvePool },
    { token: contractAddresses.usdc, contractToApprove: contractAddresses.daiUsdcUsdtCurvePool },
    { token: contractAddresses.frax, contractToApprove: contractAddresses.frax3CurvePool },
    { token: contractAddresses.usdc, contractToApprove: contractAddresses.frax3CurvePool },
    { token: contractAddresses.tusd, contractToApprove: contractAddresses.tusd3CurvePool },
    { token: contractAddresses.usdc, contractToApprove: contractAddresses.tusd3CurvePool }
  ];
  const curveRouter = await deploy(contractAddresses.volt, tokenApprovals);

  if (NetworksForVerification[hre.network.name]) {
    await verifyEtherscan(curveRouter.address, contractAddresses.volt, tokenApprovals);
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

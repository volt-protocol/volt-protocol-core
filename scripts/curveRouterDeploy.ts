import hre, { ethers } from 'hardhat';
import NetworksForVerification from '@protocol/networksForVerification';
import { getAllContractAddresses } from './utils/loadContracts';
import { CurveRouter } from '@custom-types/contracts';

async function deploy(core: string, tokenApprovals) {
  const curveRouter = await (await ethers.getContractFactory('CurveRouter')).deploy(core, tokenApprovals);

  await curveRouter.deployed();

  console.log(`\nCurve Router deployed to: ${curveRouter.address}`);

  return curveRouter;
}

async function validate(curveRouter: CurveRouter, tokenApprovals) {
  for (let i = 0; i < tokenApprovals.length; i++) {
    const token = await ethers.getContractAt('IERC20', tokenApprovals[i].token);
    token.allowance(curveRouter.address, tokenApprovals[i].contractToApprove);
  }

  console.log('\nSuccessfully Validated Deployment');
}

async function verifyEtherscan(curveRouter: string, core: string, tokenApprovals) {
  await hre.run('verify:verify', {
    address: curveRouter,
    constructorArguments: [core, tokenApprovals]
  });

  console.log('\nSuccessfully Verified Curve Router on Block Explorer');
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
    { token: contractAddresses.susd, contractToApprove: contractAddresses.susd3CurvePool },
    { token: contractAddresses.usdc, contractToApprove: contractAddresses.susd3CurvePool },
    { token: contractAddresses.rai, contractToApprove: contractAddresses.rai3CurvePool },
    { token: contractAddresses.usdc, contractToApprove: contractAddresses.rai3CurvePool },
    { token: contractAddresses.lusd, contractToApprove: contractAddresses.lusd3CurvePool },
    { token: contractAddresses.usdc, contractToApprove: contractAddresses.lusd3CurvePool },
    { token: contractAddresses.busd, contractToApprove: contractAddresses.busd3CurvePool },
    { token: contractAddresses.usdc, contractToApprove: contractAddresses.busd3CurvePool },
    { token: contractAddresses.usdn, contractToApprove: contractAddresses.usdn3CurvePool },
    { token: contractAddresses.usdc, contractToApprove: contractAddresses.usdn3CurvePool },
    { token: contractAddresses.usdp, contractToApprove: contractAddresses.usdp3CurvePool },
    { token: contractAddresses.usdc, contractToApprove: contractAddresses.usdp3CurvePool }
  ];

  const curveRouter = await deploy(contractAddresses.core, tokenApprovals);

  await validate(curveRouter, tokenApprovals);

  if (NetworksForVerification[hre.network.name]) {
    await verifyEtherscan(curveRouter.address, contractAddresses.core, tokenApprovals);
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

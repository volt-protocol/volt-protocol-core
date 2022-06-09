import config from './config';
import { getAllContracts, getAllContractAddresses } from '@scripts/utils/loadContracts';
import { ethers } from 'hardhat';
import '@nomiclabs/hardhat-ethers';

const { PCV_GUARD_ADMIN_ROLE, PCV_GUARD_ROLE } = config;

async function configuration() {
  const deployer = (await ethers.getSigners())[0];

  const addresses = await getAllContractAddresses();
  const {
    arbitrumOptimisticTimelock,
    arbitrumOraclePassThrough,
    arbitrumCore,
    arbitrumPCVGuardAdmin,
    arbitrumPCVGuardian
  } = await getAllContracts();

  /// -------- Oracle Actions --------

  /// transfer ownership to the multisig
  await arbitrumOraclePassThrough.transferOwnership(addresses.arbitrumProtocolMultisig);

  /// -------- PCV Guardian Actions --------

  // Grant PCV Controller and Guardian Roles to the PCV Guardian Contract
  await arbitrumCore.grantPCVController(arbitrumPCVGuardian.address);
  await arbitrumCore.grantGuardian(arbitrumPCVGuardian.address);

  // Create the PCV_GUARD_ADMIN Role and Grant to the PCV Guard Admin Contract
  await arbitrumCore.createRole(PCV_GUARD_ADMIN_ROLE, await arbitrumCore.GOVERN_ROLE());
  await arbitrumCore.grantRole(PCV_GUARD_ADMIN_ROLE, arbitrumPCVGuardAdmin.address);

  // Create the PCV Guard Role and grant the role to PCV Guards via the PCV Guard Admin contract
  await arbitrumCore.createRole(PCV_GUARD_ROLE, PCV_GUARD_ADMIN_ROLE);
  await arbitrumPCVGuardAdmin.grantPCVGuardRole(addresses.pcvGuardEOA1);
  await arbitrumPCVGuardAdmin.grantPCVGuardRole(addresses.pcvGuardEOA2);

  /// -------- Core Multisig and Timelock Actions --------

  await arbitrumCore.grantGovernor(addresses.arbitrumProtocolMultisig); /// give multisig the governor role
  await arbitrumCore.grantPCVController(addresses.arbitrumProtocolMultisig); /// give multisig the PCV controller role

  await arbitrumCore.grantGovernor(arbitrumOptimisticTimelock.address); /// give timelock the governor role
  await arbitrumCore.grantPCVController(arbitrumOptimisticTimelock.address); /// give timelock the PCV controller role

  /// -------- Deployer Revokes Governor --------

  /// deployer revokes their governor role from core
  await arbitrumCore.revokeGovernor(deployer.address);

  console.log(`\n ~~~~~ Configured Contracts on Arbitrum Successfully ~~~~~ \n`);
}

configuration()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });

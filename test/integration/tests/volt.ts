import chai, { expect } from 'chai';
import CBN from 'chai-bn';
import { solidity } from 'ethereum-waffle';
import { ethers } from 'hardhat';
import { NamedContracts } from '@custom-types/types';
import { expectRevert, resetFork, ZERO_ADDRESS } from '@test/helpers';
import proposals from '@test/integration/proposals_config';
import { TestEndtoEndCoordinator } from '@test/integration/setup';
import { Volt } from '@custom-types/contracts';
import { Signer } from '@ethersproject/abstract-signer';

before(async () => {
  chai.use(CBN(ethers.BigNumber));
  chai.use(solidity);
  await resetFork();
});

describe.only('e2e-volt', function () {
  let contracts: NamedContracts;
  let deployAddress: string;
  let deploySigner: Signer;
  let e2eCoord: TestEndtoEndCoordinator;
  let doLogging: boolean;
  let volt: Volt;

  before(async function () {
    // Setup test environment and get contracts
    const version = 1;
    deployAddress = (await ethers.getSigners())[0].address;
    if (!deployAddress) throw new Error(`No deploy address!`);

    doLogging = Boolean(process.env.LOGGING);

    const config = {
      logging: doLogging,
      deployAddress: deployAddress,
      version: version
    };

    e2eCoord = new TestEndtoEndCoordinator(config, proposals);

    doLogging && console.log(`Loading environment...`);
    ({ contracts } = await e2eCoord.loadEnvironment());
    doLogging && console.log(`Environment loaded.`);

    volt = contracts.volt as Volt;
    deploySigner = await ethers.getSigner(deployAddress);
  });

  /* Test disabled until restrictedPermissions is deployed. */
  describe.skip('CoreRef Functionality', async function () {
    it('setCore', async function () {
      expect(await contracts.core.isGovernor(deployAddress)).to.be.true;
    });

    it('pause/unpause', async function () {
      await contracts.core.grantGuardian(deployAddress);
      expect(await contracts.core.isGuardian(deployAddress)).to.be.true;

      await volt.connect(deploySigner).pause();
      expect(await volt.paused()).to.be.true;
      await volt.connect(deploySigner).unpause();
      expect(await volt.paused()).to.be.false;
    });
  });
});

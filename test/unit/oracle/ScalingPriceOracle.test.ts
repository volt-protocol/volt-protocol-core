import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
  expectApprox,
  expectRevert,
  getAddresses,
  getCore,
  getImpersonatedSigner,
  increaseTime,
  ZERO_ADDRESS
} from '@test/helpers';
import { ScalingPriceOracle } from '@custom-types/contracts';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { forceEth } from '@test/integration/setup/utils';

describe('ScalingPriceOracle', function () {
  const updateFrequency = 2_592_000;
  const oneYear = 31_557_600;
  let scalingPriceOracle: ScalingPriceOracle;
  const scale = ethers.constants.WeiPerEther;
  const toBN = ethers.BigNumber.from;
  let core: Contract;
  let governorSigner: SignerWithAddress;
  let guardianSigner: SignerWithAddress;

  before(async function () {
    const { governorAddress, guardianAddress } = await getAddresses();
    governorSigner = await getImpersonatedSigner(governorAddress);
    guardianSigner = await getImpersonatedSigner(guardianAddress);
    await forceEth(governorAddress);
    await forceEth(guardianAddress);
  });

  beforeEach(async function () {
    core = await getCore();
    const scalingPriceOracleFactory = await ethers.getContractFactory('ScalingPriceOracle');
    scalingPriceOracle = await scalingPriceOracleFactory.deploy(
      updateFrequency,
      1_000,
      1_000,
      1_000,
      core.address,
      ZERO_ADDRESS
    );
  });

  describe('init', function () {
    it('getCurrentOraclePrice returns initial price correctly', async function () {
      expect(await scalingPriceOracle.oraclePrice()).to.be.equal(scale);
      expect(await scalingPriceOracle.getCurrentOraclePrice()).to.be.equal(scale);
    });

    it('isTimeEnded is false on construction', async function () {
      expect(await scalingPriceOracle.isTimeEnded()).to.be.false;
    });

    it('core is set correctly', async function () {
      expect(await scalingPriceOracle.core()).to.be.equal(core.address);
      expect(await scalingPriceOracle.getCurrentOraclePrice()).to.be.equal(scale);
    });
  });

  describe('timed', function () {
    it('isTimeEnded is true after advancing the update frequency', async function () {
      await increaseTime(updateFrequency);
      expect(await scalingPriceOracle.isTimeEnded()).to.be.true;
    });
  });

  describe('positive scale', function () {
    it('getCurrentOraclePrice returns correctly after time has passed', async function () {
      await increaseTime(updateFrequency);
      const expectedPrice = toBN(scale).add(toBN(scale).mul(1000).div(10000).mul(2_592_000).div(oneYear));

      expect(await scalingPriceOracle.getCurrentOraclePrice()).to.be.equal(expectedPrice);
    });
  });

  describe('negative scaling', function () {
    beforeEach(async function () {
      const scalingPriceOracleFactory = await ethers.getContractFactory('ScalingPriceOracle');
      scalingPriceOracle = await scalingPriceOracleFactory.deploy(
        updateFrequency,
        -1_000,
        1_000,
        1_000,
        core.address,
        ZERO_ADDRESS
      );
    });

    it('getCurrentOraclePrice returns negative price correctly after time has passed', async function () {
      await increaseTime(updateFrequency);
      const expectedPrice = toBN(scale).add(toBN(scale).mul(-1000).div(10000).mul(2_592_000).div(oneYear));

      expect(await scalingPriceOracle.getCurrentOraclePrice()).to.be.equal(expectedPrice);
    });
  });

  describe('timed', function () {
    it('isTimeEnded is true after advancing the update frequency', async function () {
      await increaseTime(updateFrequency);
      expect(await scalingPriceOracle.isTimeEnded()).to.be.true;
    });
  });

  describe('positive scale', function () {
    it('getCurrentOraclePrice returns correctly after time has passed', async function () {
      const expectedPrice = toBN(scale).add(toBN(scale).mul(1000).div(10000).mul(2_592_000).div(oneYear));
      await increaseTime(updateFrequency);

      expect(await scalingPriceOracle.getCurrentOraclePrice()).to.be.equal(expectedPrice);
    });

    it('can compound after a year', async function () {
      const expectedPrice = toBN(scale).add(
        toBN(scale)
          .mul(1000)
          .div(10000)
          .mul(oneYear + 1)
          .div(oneYear)
      );

      await increaseTime(oneYear);

      await expectApprox(await scalingPriceOracle.getCurrentOraclePrice(), expectedPrice);
      await scalingPriceOracle.connect(governorSigner).compoundInterest();
      await expectApprox(await scalingPriceOracle.oraclePrice(), expectedPrice);
    });
  });

  describe('acl', function () {
    it('non governor cannot compound interest', async function () {
      await expectRevert(scalingPriceOracle.compoundInterest(), 'CoreRef: Caller is not governor or guardian or admin');
    });

    it('guardian can compound interest', async function () {
      await increaseTime(updateFrequency);
      await scalingPriceOracle.connect(guardianSigner).compoundInterest();
    });
  });
});

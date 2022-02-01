import { expect } from 'chai';
import hre, { ethers } from 'hardhat';
import { increaseTime } from '@test/helpers';
import { ScalingPriceOracle } from '@custom-types/contracts';

describe('ScalingPriceOracle', function () {
  const updateFrequency = 2_592_000;
  const oneYear = 31_557_600;
  let scalingPriceOracle: ScalingPriceOracle;
  const scale = ethers.constants.WeiPerEther;
  const toBN = ethers.BigNumber.from;

  beforeEach(async function () {
    const scalingPriceOracleFactory = await ethers.getContractFactory('ScalingPriceOracle');
    scalingPriceOracle = await scalingPriceOracleFactory.deploy(updateFrequency, 1_000);
  });

  describe('init', function () {
    it('getCurrentOraclePrice returns initial price correctly', async function () {
      expect(await scalingPriceOracle.oraclePrice()).to.be.equal(scale);
      expect(await scalingPriceOracle.getCurrentOraclePrice()).to.be.equal(scale);
    });

    it('isTimeEnded is false on construction', async function () {
      expect(await scalingPriceOracle.isTimeEnded()).to.be.false;
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
      scalingPriceOracle = await scalingPriceOracleFactory.deploy(updateFrequency, -1_000);
    });

    it('getCurrentOraclePrice returns negative price correctly after time has passed', async function () {
      await increaseTime(updateFrequency);
      const expectedPrice = toBN(scale).add(toBN(scale).mul(-1000).div(10000).mul(2_592_000).div(oneYear));

      expect(await scalingPriceOracle.getCurrentOraclePrice()).to.be.equal(expectedPrice);
    });
  });
});

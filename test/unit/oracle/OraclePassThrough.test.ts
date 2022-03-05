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
import { MockChainlinkSingleUpdateOracle, OraclePassThrough, ScalingPriceOracle } from '@custom-types/contracts';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { forceEth } from '@test/integration/setup/utils';
import { getContractAddress } from '@ethersproject/address';

describe('OraclePassThrough', function () {
  const updateFrequency = 2_419_200;
  let scalingPriceOracle: ScalingPriceOracle;
  const scale = ethers.constants.WeiPerEther;
  const toBN = ethers.BigNumber.from;
  let core: Contract;
  let governorSigner: SignerWithAddress;
  let guardianSigner: SignerWithAddress;
  let mockChainlinkOracle: MockChainlinkSingleUpdateOracle;
  let oraclePassThrough: OraclePassThrough;
  const duration = 86400 * 28;

  before(async function () {
    const { governorAddress, guardianAddress } = await getAddresses();
    governorSigner = await getImpersonatedSigner(governorAddress);
    guardianSigner = await getImpersonatedSigner(guardianAddress);
    await forceEth(governorAddress);
    await forceEth(guardianAddress);
  });

  beforeEach(async function () {
    core = await getCore();
    const oraclePassThroughFactory = await ethers.getContractFactory('OraclePassThrough');
    const scalingPriceOracleFactory = await ethers.getContractFactory('ScalingPriceOracle');
    const mockChainLinkOracleFactory = await ethers.getContractFactory('MockChainlinkSingleUpdateOracle');

    const [deployer] = await ethers.getSigners(); /// get the tx nonce of the Chainlink Oracle deploy tx
    const transactionCount = toBN(await deployer.getTransactionCount()).add(1);
    const mockChainLinkOracleAddress = getContractAddress({
      from: deployer.address,
      nonce: transactionCount
    });

    scalingPriceOracle = await scalingPriceOracleFactory.deploy(1_000, 1_000, core.address, mockChainLinkOracleAddress);
    mockChainlinkOracle = await mockChainLinkOracleFactory.deploy(scalingPriceOracle.address);
    oraclePassThrough = await oraclePassThroughFactory.deploy(core.address, scalingPriceOracle.address);
  });

  describe('init', function () {
    it('getCurrentOraclePrice returns initial price correctly', async function () {
      expect(await scalingPriceOracle.oraclePrice()).to.be.equal(scale);
      const interestPerSecond = await scalingPriceOracle.getInterestAccruedPerSecond();

      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;

      const timeDelta = toBN(timestamp).sub(await scalingPriceOracle.startTime());
      await expectApprox(await oraclePassThrough.getCurrentOraclePrice(), scale.add(timeDelta.mul(interestPerSecond)));
    });

    it('read returns initial price correctly', async function () {
      expect(await scalingPriceOracle.oraclePrice()).to.be.equal(scale);
      const interestPerSecond = await scalingPriceOracle.getInterestAccruedPerSecond();

      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;

      const timeDelta = toBN(timestamp).sub(await scalingPriceOracle.startTime());
      const { price, valid } = await oraclePassThrough.read();
      await expectApprox(price.value, scale.add(timeDelta.mul(interestPerSecond)));
      expect(valid).to.be.true;
    });

    it('isTimeEnded is false on construction', async function () {
      expect(await scalingPriceOracle.isTimeEnded()).to.be.false;
    });

    it('core is set correctly', async function () {
      expect(await scalingPriceOracle.core()).to.be.equal(core.address);
    });

    it('chainlink oracle is correctly wired into Scaling Price Oracle', async function () {
      expect(await scalingPriceOracle.chainlinkCPIOracle()).to.be.equal(mockChainlinkOracle.address);
      expect(await mockChainlinkOracle.scalingPriceOracle()).to.be.equal(scalingPriceOracle.address);
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
      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      const timeDelta = toBN(timestamp).sub(await scalingPriceOracle.startTime());

      await increaseTime(toBN(updateFrequency).sub(timeDelta));

      const expectedPrice = toBN(scale).add(toBN(scale).mul(1000).div(10000).mul(updateFrequency).div(duration));

      expect(await oraclePassThrough.getCurrentOraclePrice()).to.be.equal(expectedPrice);
    });
  });

  describe('Chainlink Oracle Sets New Positive Value', function () {
    const newChangeRateBasisPoints = 2_500;
    let checkPoint;

    beforeEach(async () => {
      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      const timeDelta = toBN(timestamp).sub(await scalingPriceOracle.startTime());

      await increaseTime(toBN(updateFrequency).sub(timeDelta));

      checkPoint = toBN(await oraclePassThrough.getCurrentOraclePrice()).sub(scale);
      await mockChainlinkOracle.updateOracleAPRBasisPoints(newChangeRateBasisPoints);
      await increaseTime(updateFrequency);
    });

    it('chainlink oracle can update scaling price oracle annual change rate basis points', async function () {
      expect(await scalingPriceOracle.monthlyChangeRateBasisPoints()).to.be.equal(newChangeRateBasisPoints);
    });

    it('getCurrentOraclePrice returns correctly after time has passed with new change rate', async function () {
      const interestPerSecond = await scalingPriceOracle.getInterestAccruedPerSecond();

      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      const timeDelta = toBN(timestamp).sub(await scalingPriceOracle.startTime());
      const interestAccrued = timeDelta.mul(interestPerSecond);

      const expectedPrice = toBN(scale.add(checkPoint)).add(interestAccrued);

      /// this is usually off by 1 second worth of interest because of all the calculations done on expected price
      /// this is why expectApprox is used
      await expectApprox(await oraclePassThrough.getCurrentOraclePrice(), expectedPrice);
    });
  });

  describe('negative scaling', function () {
    beforeEach(async function () {
      const oraclePassThroughFactory = await ethers.getContractFactory('OraclePassThrough');
      const scalingPriceOracleFactory = await ethers.getContractFactory('ScalingPriceOracle');
      scalingPriceOracle = await scalingPriceOracleFactory.deploy(-1_000, 1_000, core.address, ZERO_ADDRESS);
      oraclePassThrough = await oraclePassThroughFactory.deploy(core.address, scalingPriceOracle.address);
    });

    it('getCurrentOraclePrice returns negative price correctly after time has passed', async function () {
      await increaseTime(updateFrequency);
      const expectedPrice = toBN(scale).add(toBN(scale).mul(-1000).div(10000).mul(updateFrequency).div(duration));

      expect(await oraclePassThrough.getCurrentOraclePrice()).to.be.equal(expectedPrice);
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
      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      const timeDelta = toBN(timestamp).sub(await scalingPriceOracle.startTime());

      await increaseTime(toBN(updateFrequency).sub(timeDelta));
      const expectedPrice = toBN(scale).add(toBN(scale).mul(1000).div(10000).mul(updateFrequency).div(duration));

      expect(await oraclePassThrough.getCurrentOraclePrice()).to.be.equal(expectedPrice);
    });

    it('can compound after 28 days', async function () {
      const expectedPrice = toBN(scale).add(toBN(scale).mul(1000).div(10000));

      await increaseTime(duration);

      await expectApprox(await oraclePassThrough.getCurrentOraclePrice(), expectedPrice);
      await scalingPriceOracle.connect(governorSigner).compoundInterest();
      await expectApprox(await scalingPriceOracle.oraclePrice(), expectedPrice);
    });

    it('price does not increase after 28 days', async function () {
      const expectedPrice = toBN(scale).add(toBN(scale).mul(1000).div(10000));

      await increaseTime(duration);
      await expectApprox(await oraclePassThrough.getCurrentOraclePrice(), expectedPrice);

      await increaseTime(duration);
      await expectApprox(await oraclePassThrough.getCurrentOraclePrice(), expectedPrice);
    });
  });

  describe('acl', function () {
    describe('updateScalingPriceOracle', function () {
      it('non governor cannot change scaling price oracle', async function () {
        await expectRevert(
          oraclePassThrough.updateScalingPriceOracle(scalingPriceOracle.address),
          'CoreRef: Caller is not a governor'
        );
      });

      it('governor can change scaling price oracle address', async function () {
        const scalingPriceOracleFactory = await ethers.getContractFactory('ScalingPriceOracle');
        const newScalingPriceOracle = await scalingPriceOracleFactory.deploy(1_000, 1_000, core.address, ZERO_ADDRESS);

        await oraclePassThrough.connect(governorSigner).updateScalingPriceOracle(newScalingPriceOracle.address);

        expect(await oraclePassThrough.scalingPriceOracle()).to.be.eq(newScalingPriceOracle.address);
      });
    });
  });
});

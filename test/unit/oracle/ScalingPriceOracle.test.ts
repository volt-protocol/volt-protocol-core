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
import { MockChainlinkSingleUpdateOracle, ScalingPriceOracle } from '@custom-types/contracts';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { forceEth } from '@test/integration/setup/utils';
import { getContractAddress } from '@ethersproject/address';

describe('ScalingPriceOracle', function () {
  const updateFrequency = 2_419_200;
  const oneYear = 31_557_600;
  let scalingPriceOracle: ScalingPriceOracle;
  const scale = ethers.constants.WeiPerEther;
  const toBN = ethers.BigNumber.from;
  let core: Contract;
  let governorSigner: SignerWithAddress;
  let guardianSigner: SignerWithAddress;
  let mockChainlinkOracle: MockChainlinkSingleUpdateOracle;

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
    const mockChainLinkOracleFactory = await ethers.getContractFactory('MockChainlinkSingleUpdateOracle');

    const [deployer] = await ethers.getSigners(); /// get the tx nonce of the Chainlink Oracle deploy tx
    const transactionCount = toBN(await deployer.getTransactionCount()).add(1);
    const mockChainLinkOracleAddress = getContractAddress({
      from: deployer.address,
      nonce: transactionCount
    });

    scalingPriceOracle = await scalingPriceOracleFactory.deploy(1_000, 1_000, core.address, mockChainLinkOracleAddress);
    mockChainlinkOracle = await mockChainLinkOracleFactory.deploy(scalingPriceOracle.address);
  });

  describe('init', function () {
    it('getCurrentOraclePrice returns initial price correctly', async function () {
      expect(await scalingPriceOracle.oraclePrice()).to.be.equal(scale);
      const interestPerSecond = await scalingPriceOracle.getInterestAccruedPerSecond();

      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;

      const timeDelta = toBN(timestamp).sub(await scalingPriceOracle.startTime());
      expect(await scalingPriceOracle.getCurrentOraclePrice()).to.be.equal(scale.add(timeDelta.mul(interestPerSecond)));
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

      const expectedPrice = toBN(scale).add(toBN(scale).mul(1000).div(10000).mul(updateFrequency).div(oneYear));

      expect(await scalingPriceOracle.getCurrentOraclePrice()).to.be.equal(expectedPrice);
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

      checkPoint = toBN(await scalingPriceOracle.getCurrentOraclePrice()).sub(scale);
      await mockChainlinkOracle.updateOracleAPRBasisPoints(newChangeRateBasisPoints);
      await increaseTime(updateFrequency);
    });

    it('chainlink oracle can update scaling price oracle annual change rate basis points', async function () {
      expect(await scalingPriceOracle.annualChangeRateBasisPoints()).to.be.equal(newChangeRateBasisPoints);
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
      await expectApprox(await scalingPriceOracle.getCurrentOraclePrice(), expectedPrice);
    });
  });

  describe('negative scaling', function () {
    beforeEach(async function () {
      const scalingPriceOracleFactory = await ethers.getContractFactory('ScalingPriceOracle');
      scalingPriceOracle = await scalingPriceOracleFactory.deploy(-1_000, 1_000, core.address, ZERO_ADDRESS);
    });

    it('getCurrentOraclePrice returns negative price correctly after time has passed', async function () {
      await increaseTime(updateFrequency);
      const expectedPrice = toBN(scale).add(toBN(scale).mul(-1000).div(10000).mul(updateFrequency).div(oneYear));

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
      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      const timeDelta = toBN(timestamp).sub(await scalingPriceOracle.startTime());

      await increaseTime(toBN(updateFrequency).sub(timeDelta));
      const expectedPrice = toBN(scale).add(toBN(scale).mul(1000).div(10000).mul(updateFrequency).div(oneYear));

      expect(await scalingPriceOracle.getCurrentOraclePrice()).to.be.equal(expectedPrice);
    });

    it('can compound after a year', async function () {
      const expectedPrice = toBN(scale).add(toBN(scale).mul(1000).div(10000));

      await increaseTime(oneYear);

      await expectApprox(await scalingPriceOracle.getCurrentOraclePrice(), expectedPrice);
      await scalingPriceOracle.connect(governorSigner).compoundInterest();
      await expectApprox(await scalingPriceOracle.oraclePrice(), expectedPrice);
    });
  });

  describe('acl', function () {
    describe('compoundInterest', function () {
      it('non governor cannot compound interest', async function () {
        await expectRevert(
          scalingPriceOracle.compoundInterest(),
          'CoreRef: Caller is not governor or guardian or admin'
        );
      });

      it('guardian can compound interest', async function () {
        const startingOraclePrice = await scalingPriceOracle.oraclePrice();
        await increaseTime(updateFrequency);
        await scalingPriceOracle.connect(guardianSigner).compoundInterest();

        const endingOraclePrice = await scalingPriceOracle.oraclePrice();
        expect(endingOraclePrice).to.be.gt(startingOraclePrice);
      });
    });

    describe('updateOracleChangeRateGovernor', function () {
      beforeEach(async function () {
        await increaseTime(updateFrequency);
      });

      it('updateOracleChangeRateGovernor can update change rate as governor and new rate is within deviation threshold', async function () {
        const newChangeRateBasisPoints = 1_099;
        await scalingPriceOracle.connect(governorSigner).updateOracleChangeRateGovernor(newChangeRateBasisPoints);
        expect(await scalingPriceOracle.annualChangeRateBasisPoints()).to.be.equal(newChangeRateBasisPoints);
      });

      it('updateOracleChangeRateGovernor fails when outside of acceptable deviation threshold for admin change rate update', async function () {
        const newChangeRateBasisPoints = 3_000;
        await expectRevert(
          scalingPriceOracle.connect(governorSigner).updateOracleChangeRateGovernor(newChangeRateBasisPoints),
          'ScalingPriceOracle: new change rate is outside of allowable deviation'
        );
      });

      it('updateOracleChangeRateGovernor fails when caller does not have permissions', async function () {
        await expectRevert(
          scalingPriceOracle.updateOracleChangeRateGovernor(3_000),
          'CoreRef: Caller is not a governor'
        );
      });
    });

    describe('emergencyUpdateOraclePrice', function () {
      it('emergencyUpdateOraclePrice updates oracle price correctly', async function () {
        const newPrice = scale.mul(100);
        const startingPrice = await scalingPriceOracle.oraclePrice();
        await scalingPriceOracle.connect(guardianSigner).emergencyUpdateOraclePrice(newPrice);
        const endingPrice = await scalingPriceOracle.oraclePrice();

        expect(newPrice).to.be.equal(endingPrice);
        expect(endingPrice).to.not.be.equal(startingPrice);
      });

      it('emergencyUpdateOraclePrice fails when caller is not guardian or governor', async function () {
        await expectRevert(
          scalingPriceOracle.updateOracleChangeRateGovernor(3_000),
          'CoreRef: Caller is not a governor'
        );
      });
    });

    describe('updateChainLinkCPIOracle', function () {
      it('updateChainLinkCPIOracle succeeds when permissioned user calls', async function () {
        await scalingPriceOracle.connect(governorSigner).updateChainLinkCPIOracle(ZERO_ADDRESS);
        expect(await scalingPriceOracle.chainlinkCPIOracle()).to.be.equal(ZERO_ADDRESS);
      });

      it('updateChainLinkCPIOracle fails when caller does not have permissions', async function () {
        await expectRevert(
          scalingPriceOracle.updateOracleChangeRateGovernor(3_000),
          'CoreRef: Caller is not a governor'
        );
      });
    });

    describe('updatePeriod', function () {
      it('updatePeriod succeeds when permissioned user calls', async function () {
        const newPeriod = 86400;
        await scalingPriceOracle.connect(governorSigner).updatePeriod(newPeriod);
      });

      it('updatePeriod fails when caller does not have permissions', async function () {
        await expectRevert(
          scalingPriceOracle.updatePeriod(3_000),
          'CoreRef: Caller is not a governor or contract admin'
        );
      });
    });

    describe('oracleUpdateChangeRate', function () {
      let chainLinkOracle: SignerWithAddress;
      beforeEach(async function () {
        chainLinkOracle = await getImpersonatedSigner(mockChainlinkOracle.address);
        await forceEth(mockChainlinkOracle.address);
        await increaseTime(updateFrequency);
      });

      it('oracleUpdateChangeRate succeeds when permissioned user calls', async function () {
        const newChangeRate = 10000;
        const oldChangeRate = await scalingPriceOracle.annualChangeRateBasisPoints();

        await expect(await scalingPriceOracle.connect(chainLinkOracle).oracleUpdateChangeRate(newChangeRate))
          .to.emit(scalingPriceOracle, 'CPIAnnualChangeRateUpdate')
          .withArgs(oldChangeRate, newChangeRate);
      });

      it('oracleUpdateChangeRate succeeds and does not emit event when permissioned user calls with current exchange rate', async function () {
        const oldChangeRate = await scalingPriceOracle.annualChangeRateBasisPoints();
        await expect(
          await scalingPriceOracle.connect(chainLinkOracle).oracleUpdateChangeRate(oldChangeRate)
        ).to.not.emit(scalingPriceOracle, 'CPIAnnualChangeRateUpdate');
      });

      it('oracleUpdateChangeRate fails when caller does not have permissions', async function () {
        await expectRevert(
          scalingPriceOracle.oracleUpdateChangeRate(3_000),
          'ScalingPriceOracle: caller is not chainlink oracle'
        );
      });
    });
  });
});

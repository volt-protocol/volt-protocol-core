import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract, utils } from 'ethers';
import { expectRevert, ZERO_ADDRESS } from '@test/helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { keccak256 } from 'ethers/lib/utils';

const toBN = ethers.BigNumber.from;
const scale = ethers.constants.WeiPerEther;

describe('ChainlinkOracle', function () {
  const jobid = keccak256(utils.toUtf8Bytes('jobid'));
  let chainlinkOracle: Contract;
  const initialQueue = [120, 240];
  let owner: SignerWithAddress;
  let chainlinkOperator: SignerWithAddress;

  beforeEach(async function () {
    [owner, chainlinkOperator] = await ethers.getSigners();
    const mockScalingOracleFactory = await ethers.getContractFactory('MockScalingPriceOracle');
    const chainlinkOracleFactory = await ethers.getContractFactory('ChainlinkOracle');
    const mockOracle = await mockScalingOracleFactory.deploy(scale, 1_000, ZERO_ADDRESS);
    chainlinkOracle = await chainlinkOracleFactory.deploy(
      mockOracle.address,
      chainlinkOperator.address,
      jobid,
      scale,
      initialQueue
    );
  });

  describe('apr basis points 10_000', function () {
    beforeEach(async function () {});

    it('queue returns initial APR correctly', async function () {});
  });

  describe('ACL', function () {
    beforeEach(async function () {});
    describe('requestCPIData', function () {
      it.skip('succeeds when caller is owner', async function () {
        await chainlinkOracle.connect(owner).requestCPIData();
      });

      it('fails when caller is not owner', async function () {
        await expectRevert(
          chainlinkOracle.connect(chainlinkOperator).requestCPIData(),
          'Ownable: caller is not the owner'
        );
      });
    });

    describe('withdrawLink', function () {
      it.skip('succeeds when caller is owner', async function () {});
      it('fails when caller is not owner', async function () {
        await expectRevert(
          chainlinkOracle.connect(chainlinkOperator).withdrawLink(ZERO_ADDRESS, 0),
          'Ownable: caller is not the owner'
        );
      });
    });

    describe('withdrawToken', function () {
      it.skip('succeeds when caller is owner', async function () {});
      it('fails when caller is not owner', async function () {
        await expectRevert(
          chainlinkOracle.connect(chainlinkOperator).withdrawToken(ZERO_ADDRESS, ZERO_ADDRESS, 10_000),
          'Ownable: caller is not the owner'
        );
      });
    });

    describe('setFee', function () {
      it.skip('succeeds when caller is owner', async function () {});
      it('fails when caller is not owner', async function () {
        await expectRevert(
          chainlinkOracle.connect(chainlinkOperator).setFee(scale.mul(10)),
          'Ownable: caller is not the owner'
        );
      });
    });

    describe('setScalingPriceOracle', function () {
      it('succeeds when caller is owner', async function () {
        await chainlinkOracle.connect(owner).setScalingPriceOracle(ZERO_ADDRESS);
        expect(await chainlinkOracle.voltOracle()).to.be.equal(ZERO_ADDRESS);
      });

      it('fails when caller is not owner', async function () {
        await expectRevert(
          chainlinkOracle.connect(chainlinkOperator).setScalingPriceOracle(ZERO_ADDRESS),
          'Ownable: caller is not the owner'
        );
      });
    });

    describe('setChainlinkOracleAddress', function () {
      it('succeeds when caller is owner', async function () {
        await chainlinkOracle.connect(owner).setChainlinkOracleAddress(ZERO_ADDRESS);
        expect(await chainlinkOracle.oracle()).to.be.equal(ZERO_ADDRESS);
      });

      it('fails when caller is not owner', async function () {
        await expectRevert(
          chainlinkOracle.connect(chainlinkOperator).setChainlinkOracleAddress(ZERO_ADDRESS),
          'Ownable: caller is not the owner'
        );
      });
    });

    describe('setJobID', function () {
      const jobId = keccak256(utils.toUtf8Bytes('jobId'));

      it('succeeds when caller is owner', async function () {
        await chainlinkOracle.connect(owner).setJobID(jobId);
        expect(await chainlinkOracle.jobId()).to.be.equal(jobId);
      });

      it('fails when caller is not owner', async function () {
        await expectRevert(
          chainlinkOracle.connect(chainlinkOperator).setJobID(jobId),
          'Ownable: caller is not the owner'
        );
      });
    });
  });
});

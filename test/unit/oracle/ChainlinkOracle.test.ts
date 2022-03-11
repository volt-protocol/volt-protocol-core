import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract, utils } from 'ethers';
import { expectRevert, ZERO_ADDRESS } from '@test/helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { keccak256 } from 'ethers/lib/utils';
import { getCore } from '@test/helpers';
import { Core, MockERC20, MockScalingPriceOracle } from '@custom-types/contracts';
const toBN = ethers.BigNumber.from;
const scale = ethers.constants.WeiPerEther;

describe('ChainlinkOracle', function () {
  const jobid = keccak256(utils.toUtf8Bytes('jobid'));
  let chainlinkOracle: Contract;
  let owner: SignerWithAddress;
  let chainlinkOperator: SignerWithAddress;
  let core: Core;
  let mockOracle: MockScalingPriceOracle;
  const currentMonth = toBN(250);
  const previousMonth = toBN(240);

  beforeEach(async function () {
    core = await getCore();
    [owner, chainlinkOperator] = await ethers.getSigners();
    const mockScalingOracleFactory = await ethers.getContractFactory('MockScalingPriceOracle');
    const chainlinkOracleFactory = await ethers.getContractFactory('ChainlinkOracle');
    mockOracle = await mockScalingOracleFactory.deploy(scale, 1_000, core.address);
    chainlinkOracle = await chainlinkOracleFactory.deploy(
      mockOracle.address,
      chainlinkOperator.address,
      jobid,
      scale,
      currentMonth,
      previousMonth
    );
  });

  describe('apr basis points', function () {
    it('returns initial APR correctly', async function () {
      const expectedAPR = currentMonth.sub(previousMonth).mul(10_000).div(previousMonth);
      const apr = await chainlinkOracle.getMonthlyAPR();
      expect(apr).to.be.equal(expectedAPR);
    });
  });

  describe('ACL', function () {
    beforeEach(async function () {});
    describe('requestCPIData', function () {
      it.skip('succeeds when caller is owner', async function () {});

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
      let token: MockERC20;
      const mintAmount = 100;

      beforeEach(async function () {
        token = await (await ethers.getContractFactory('MockERC20')).deploy();
        await token.mint(chainlinkOracle.address, mintAmount);
      });

      it('succeeds when caller is owner', async function () {
        await chainlinkOracle.connect(owner).withdrawToken(token.address, owner.address, mintAmount);

        expect(await token.balanceOf(owner.address)).to.be.equal(mintAmount);
        expect(await token.balanceOf(chainlinkOracle.address)).to.be.equal(0);
      });

      it('fails when caller is not owner', async function () {
        await expectRevert(
          chainlinkOracle.connect(chainlinkOperator).withdrawToken(ZERO_ADDRESS, ZERO_ADDRESS, 10_000),
          'Ownable: caller is not the owner'
        );
      });
    });

    describe('setFee', function () {
      it('succeeds when caller is owner', async function () {
        await chainlinkOracle.connect(owner).setFee(scale);
        expect(await chainlinkOracle.fee()).to.be.equal(scale);
      });

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

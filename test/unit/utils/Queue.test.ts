import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract } from 'ethers';
import { expectRevert, getAddresses, getCore, getImpersonatedSigner, increaseTime, ZERO_ADDRESS } from '@test/helpers';

const toBN = ethers.BigNumber.from;

describe('Queue', function () {
  let queue: Contract;

  describe('apr basis points 10_000', function () {
    const initialQueue = [120, 130, 140, 150, 160, 170, 180, 190, 200, 210, 220, 240].reverse();
    beforeEach(async function () {
      const queueFactory = await ethers.getContractFactory('Queue');
      queue = await queueFactory.deploy(initialQueue);
    });

    it('queue returns initial APR correctly', async function () {
      const expectedAPR = 10_000;
      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
    });
  });

  describe('apr basis points -10_000', function () {
    const initialQueue = [240, 230, 220, 210, 200, 190, 180, 170, 160, 150, 140, 1].reverse();
    beforeEach(async function () {
      const queueFactory = await ethers.getContractFactory('Queue');
      queue = await queueFactory.deploy(initialQueue);
    });

    it('queue returns initial APR correctly', async function () {
      const expectedAPR = toBN(-239).mul(10_000).div(initialQueue[11]);
      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
    });
  });

  describe('apr basis points 833', function () {
    const initialQueue = [120, 121, 123, 124, 125, 126, 127, 127, 128, 129, 129, 130].reverse();
    beforeEach(async function () {
      const queueFactory = await ethers.getContractFactory('Queue');
      queue = await queueFactory.deploy(initialQueue);
    });

    it('queue returns initial APR correctly', async function () {
      const expectedAPR = toBN(10).mul(10_000).div(120);
      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
    });
  });

  describe('apr basis points 833', function () {
    const initialQueue = [120, 121, 123, 124, 125, 126, 127, 127, 128, 129, 129, 130].reverse();
    beforeEach(async function () {
      const queueFactory = await ethers.getContractFactory('Queue');
      queue = await queueFactory.deploy(initialQueue);
    });

    it('queue returns initial APR correctly', async function () {
      const expectedAPR = toBN(10).mul(10_000).div(120);
      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
    });
  });
});

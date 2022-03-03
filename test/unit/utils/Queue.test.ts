import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract } from 'ethers';
import { expectRevert } from '@test/helpers';

const toBN = ethers.BigNumber.from;

describe('Queue', function () {
  let queue: Contract;

  describe('deployment fails on incomplete ttm data', function () {
    it('deployment failure', async function () {
      const initialQueue = [120, 140, 150, 160, 170, 180, 190, 200, 210, 220, 240];
      const queueFactory = await ethers.getContractFactory('Queue');
      await expectRevert(queueFactory.deploy(initialQueue), 'Queue: invalid length');
    });
  });

  describe('apr basis points 10_000', function () {
    const initialQueue = [240, 220, 210, 200, 190, 180, 170, 160, 150, 140, 130, 125, 120];
    beforeEach(async function () {
      const queueFactory = await ethers.getContractFactory('Queue');
      queue = await queueFactory.deploy(initialQueue);
    });

    it('queue returns initial APR correctly', async function () {
      const expectedAPR = 10_000;
      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
    });

    it('queue sum is correct', async function () {
      const queueSum = initialQueue.reduce((prevElem, elem) => {
        return elem + prevElem;
      }, 0);

      expect(await queue.getQueueSum()).to.be.equal(queueSum);
    });
  });

  describe('apr basis points -10_000', function () {
    const initialQueue = [1, 1, 230, 220, 210, 200, 190, 180, 170, 160, 150, 140, 240];
    beforeEach(async function () {
      const queueFactory = await ethers.getContractFactory('Queue');
      queue = await queueFactory.deploy(initialQueue);
    });

    it('queue returns initial APR correctly', async function () {
      const expectedAPR = toBN(-239).mul(10_000).div(initialQueue[12]);
      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
    });

    it('queue sum is correct', async function () {
      const queueSum = initialQueue.reduce((prevElem, elem) => {
        return elem + prevElem;
      }, 0);

      expect(await queue.getQueueSum()).to.be.equal(queueSum);
    });
  });

  describe('apr basis points 833', function () {
    const initialQueue = [130, 121, 123, 124, 125, 126, 127, 127, 127, 128, 129, 129, 120];
    beforeEach(async function () {
      const queueFactory = await ethers.getContractFactory('Queue');
      queue = await queueFactory.deploy(initialQueue);
    });

    it('queue returns initial APR correctly', async function () {
      const expectedAPR = toBN(10).mul(10_000).div(120);
      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
    });

    it('queue sum is correct', async function () {
      const queueSum = initialQueue.reduce((prevElem, elem) => {
        return elem + prevElem;
      }, 0);

      expect(await queue.getQueueSum()).to.be.equal(queueSum);
    });
  });

  describe('apr basis points 1666', function () {
    const initialQueue = [140, 129, 129, 128, 127, 127, 127, 126, 125, 124, 123, 121, 120];
    beforeEach(async function () {
      const queueFactory = await ethers.getContractFactory('Queue');
      queue = await queueFactory.deploy(initialQueue);
    });

    it('queue returns initial APR correctly', async function () {
      const expectedAPR = toBN(20).mul(10_000).div(120);
      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
    });

    it('queue sum is correct', async function () {
      const queueSum = initialQueue.reduce((prevElem, elem) => {
        return elem + prevElem;
      }, 0);

      expect(await queue.getQueueSum()).to.be.equal(queueSum);
    });
  });

  describe('can properly push an item onto the queue', function () {
    const initialQueue = [130, 129, 128, 127, 127, 127, 126, 125, 124, 123, 122, 121, 120];
    beforeEach(async function () {
      const queueFactory = await ethers.getContractFactory('MockQueue');
      queue = await queueFactory.deploy(initialQueue);
    });

    it('queue returns initial APR correctly', async function () {
      const expectedAPR = toBN(10).mul(10_000).div(120);
      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
    });

    it('queue values are correct', async function () {
      for (let i = 0; i < initialQueue.length; i++) {
        expect(await queue.queue(i)).to.be.equal(initialQueue[i]);
      }
    });

    it('can unshift to the queue', async function () {
      const newElem = 131;
      initialQueue.unshift(newElem);
      initialQueue.pop();

      await queue.unshift(newElem);

      for (let i = 0; i < initialQueue.length; i++) {
        expect(await queue.queue(i)).to.be.equal(initialQueue[i]);
      }
    });

    it('queue sum is correct after pushing to queue', async function () {
      const queueSum = initialQueue.reduce((prevElem, elem) => {
        return elem + prevElem;
      }, 0);

      expect(await queue.getQueueSum()).to.be.equal(queueSum);
    });

    it('APR is correct after pushing to queue', async function () {
      const expectedAPR = toBN(10).mul(10_000).div(121);
      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
    });

    it('can unshift to the queue', async function () {
      const newElem = 142;
      initialQueue.unshift(newElem);
      initialQueue.pop();

      await queue.unshift(newElem);

      for (let i = 0; i < initialQueue.length; i++) {
        expect(await queue.queue(i)).to.be.equal(initialQueue[i]);
      }
    });

    it('queue sum is correct after pushing to queue', async function () {
      const queueSum = initialQueue.reduce((prevElem, elem) => {
        return elem + prevElem;
      }, 0);

      expect(await queue.getQueueSum()).to.be.equal(queueSum);
    });

    it('APR is correct after pushing to queue', async function () {
      const delta = toBN(await queue.queue(0)).sub(await queue.queue(12));

      const expectedAPR = toBN(delta).mul(10_000).div(122);
      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
      expect(delta).to.be.equal(20);
    });
  });
});

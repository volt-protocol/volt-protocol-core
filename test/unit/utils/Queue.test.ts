import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract } from 'ethers';
import { expectRevert } from '@test/helpers';

const toBN = ethers.BigNumber.from;

describe('Queue', function () {
  let queue: Contract;

  describe('deployment fails on incomplete data', function () {
    it('deployment failure', async function () {
      const initialQueue = [120, 240, 0];
      const queueFactory = await ethers.getContractFactory('Queue');
      await expectRevert(queueFactory.deploy(initialQueue), 'Queue: invalid length');
    });
  });

  describe('apr basis points 10_000', function () {
    const initialQueue = [240, 120];
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
    const initialQueue = [1, 240];
    beforeEach(async function () {
      const queueFactory = await ethers.getContractFactory('Queue');
      queue = await queueFactory.deploy(initialQueue);
    });

    it('queue returns initial APR correctly', async function () {
      const expectedAPR = toBN(-239).mul(10_000).div(initialQueue[1]);
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
    const initialQueue = [130, 120];
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
    const initialQueue = [140, 120];
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
    const initialQueue = [130, 120];
    before(async function () {
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
      const expectedAPR = toBN(1).mul(10_000).div(130);
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
      const delta = toBN(await queue.queue(0)).sub(await queue.queue(1));
      const expectedAPR = toBN(delta)
        .mul(10_000)
        .div(await queue.queue(1));

      expect(await queue.getAPRFromQueue()).to.be.equal(expectedAPR);
      expect(delta).to.be.equal(11);
    });
  });
});

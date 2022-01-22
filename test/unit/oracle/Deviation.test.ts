import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Deviation } from '@custom-types/contracts';

describe('Deviation', function () {
  let deviation: Deviation;
  const deviationThreshold = 100;

  before(async function () {
    deviation = await (await ethers.getContractFactory('Deviation')).deploy(deviationThreshold);
    await deviation.deployTransaction.wait();
  });

  it('deviationThreshold is set correctly', async function () {
    expect(await deviation.maxDeviationThresholdBasisPoints()).to.be.equal(deviationThreshold);
  });

  it('deviationThreshold returns true when under the deviation threshold', async function () {
    /// only .1% difference here
    const a = 10_000;
    const b = 9_990;
    expect(await deviation.isWithinDeviationThreshold(a, b)).to.be.equal(true);
  });

  it('deviationThreshold returns true when at the deviation threshold', async function () {
    /// only 1% difference here
    const a = 10_000;
    const b = 9_900;
    expect(await deviation.isWithinDeviationThreshold(a, b)).to.be.equal(true);
  });

  it('deviationThreshold returns false when at the deviation threshold', async function () {
    /// 1.1% difference here
    const a = 10_000;
    const b = 9_890;
    expect(await deviation.isWithinDeviationThreshold(a, b)).to.be.equal(false);
  });

  it('calculateDeviationThresholdBasisPoints returns correctly', async function () {
    const a = 10_000;
    const b = 9_890;
    const expectedDeviationThresholdBasisPoints = a - b;
    expect(await deviation.calculateDeviationThresholdBasisPoints(a, b)).to.be.equal(
      expectedDeviationThresholdBasisPoints
    );
  });
});

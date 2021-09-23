import { expectRevert, getAddresses, getCore } from '../../helpers';
import { expect } from 'chai'
import hre, { ethers, artifacts } from 'hardhat';
import { Signer } from 'ethers'

const toBN = ethers.BigNumber.from
  
const ReserveStabilizer = artifacts.readArtifactSync('ReserveStabilizer');
const Fei = artifacts.readArtifactSync('Fei');
const MockOracle = artifacts.readArtifactSync('MockOracle');
const MockERC20 = artifacts.readArtifactSync('MockERC20');
const MockPCVDeposit = artifacts.readArtifactSync('MockEthUniswapPCVDeposit');

describe('ReserveStabilizer', function () {
  let userAddress;
  let governorAddress;
  let minterAddress;
  let pcvControllerAddress;

  let impersonatedSigners: { [key: string]: Signer } = { }

  before(async() => {
    const addresses = await getAddresses()

    // add any addresses you want to impersonate here
    const impersonatedAddresses = [
      addresses.userAddress,
      addresses.pcvControllerAddress,
      addresses.governorAddress,
      addresses.pcvControllerAddress,
      addresses.minterAddress,
      addresses.burnerAddress,
      addresses.beneficiaryAddress1,
      addresses.beneficiaryAddress2
    ]

    for (const address of impersonatedAddresses) {
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [address]
      })

      impersonatedSigners[address] = await ethers.getSigner(address)
    }
  });

  beforeEach(async function () {
    ({
      userAddress,
      governorAddress,
      minterAddress,
      pcvControllerAddress,
    } = await getAddresses());
    
    this.core = await getCore();

    this.fei = await ethers.getContractAt('Fei', await this.core.fei());
    this.token = await (await ethers.getContractFactory('MockERC20')).deploy();
    this.oracle = await (await ethers.getContractFactory('MockOracle')).deploy(400); // 400:1 oracle price
    this.pcvDeposit = await (await ethers.getContractFactory('MockPCVDeposit')).deploy(userAddress);

    this.reserveStabilizer = await (await ethers.getContractFactory('ReserveStabilizer')).deploy(this.core.address, this.oracle.address, this.oracle.address, this.token.address, '9000');

    await this.core.grantBurner(this.reserveStabilizer.address, {from: governorAddress});

    this.initialBalance = toBN('1000000000000000000');
    await this.token.mint(this.reserveStabilizer.address, this.initialBalance);

    await this.fei.mint(userAddress, 40000000, {from: minterAddress});  
  });

  describe('Exchange', function() {
    describe('Enough FEI', function() {
      it('exchanges for appropriate amount of token', async function() {
        const reserveBalanceBefore = await this.token.balanceOf(this.reserveStabilizer.address);
        await this.reserveStabilizer.exchangeFei(40000000, {from: userAddress});
        const reserveBalanceAfter = await this.token.balanceOf(this.reserveStabilizer.address);

        this.expectedOut = toBN('90000');
        expect(reserveBalanceBefore.sub(reserveBalanceAfter)).to.be.equal(this.expectedOut);

        expect(await this.fei.balanceOf(userAddress)).to.be.equal(toBN('0'));
        expect(await this.reserveStabilizer.balance()).to.be.equal(this.initialBalance.sub(this.expectedOut));
      });
    });

    describe('Double Oracle price', function() {
      it('exchanges for appropriate amount of token', async function() {
        await this.oracle.setExchangeRate('800');

        const reserveBalanceBefore = await this.token.balanceOf(this.reserveStabilizer.address);
        await this.reserveStabilizer.exchangeFei(40000000, {from: userAddress});
        const reserveBalanceAfter = await this.token.balanceOf(this.reserveStabilizer.address);

        this.expectedOut = toBN('45000');
        expect(reserveBalanceBefore.sub(reserveBalanceAfter)).to.be.equal(this.expectedOut);

        expect(await this.fei.balanceOf(userAddress)).to.be.equal(toBN('0'));
        expect(await this.reserveStabilizer.balance()).to.be.equal(this.initialBalance.sub(this.expectedOut));
      });
    });

    describe('Higher usd per fei', function() {
      it('exchanges for appropriate amount of token', async function() {
        await this.reserveStabilizer.setUsdPerFeiRate('9500', {from: governorAddress});

        const reserveBalanceBefore = await this.token.balanceOf(this.reserveStabilizer.address);
        await this.reserveStabilizer.exchangeFei(40000000, {from: userAddress});
        const reserveBalanceAfter = await this.token.balanceOf(this.reserveStabilizer.address);

        this.expectedOut = toBN('95000');
        expect(reserveBalanceBefore.sub(reserveBalanceAfter)).to.be.equal(this.expectedOut);

        expect(await this.fei.balanceOf(userAddress)).to.be.equal(toBN('0'));
        expect(await this.reserveStabilizer.balance()).to.be.equal(this.initialBalance.sub(this.expectedOut));
      });
    });

    describe('Not Enough FEI', function() {
      it('reverts', async function() {
        await expectRevert(this.reserveStabilizer.exchangeFei(50000000, {from: userAddress}), 'ERC20: burn amount exceeds balance');
      });
    });

    describe('Not Enough token', function() {
      it('reverts', async function() {
        await this.fei.mint(userAddress, toBN('4000000000000000000000000000'), {from: minterAddress});  
        await expectRevert(this.reserveStabilizer.exchangeFei(toBN('4000000000000000000000000000'), {from: userAddress}), 'revert');
      });
    });

    describe('Paused', function() {
      it('reverts', async function() {
        await this.reserveStabilizer.pause({from: governorAddress});
        await expectRevert(this.reserveStabilizer.exchangeFei(toBN('400000'), {from: userAddress}), 'Pausable: paused');
      });
    });
  });

  describe('Withdraw', function() {
    it('enough token succeeds', async function() {
      const reserveBalanceBefore = await this.token.balanceOf(this.reserveStabilizer.address);
      const userBalanceBefore = await this.token.balanceOf(userAddress);

      await this.reserveStabilizer.withdraw(userAddress, '10000', {from: pcvControllerAddress});
      const reserveBalanceAfter = await this.token.balanceOf(this.reserveStabilizer.address);
      const userBalanceAfter = await this.token.balanceOf(userAddress);

      expect(reserveBalanceBefore.sub(reserveBalanceAfter)).to.be.equal(toBN('10000'));
      expect(userBalanceAfter.sub(userBalanceBefore)).to.be.equal(toBN('10000'));
    });

    it('not enough token reverts', async function() {
      await expectRevert(this.reserveStabilizer.withdraw(userAddress, '10000000000000000000', {from: pcvControllerAddress}), 'revert');
    });

    it('non pcvController', async function() {
      await expectRevert(this.reserveStabilizer.withdraw(userAddress, '10000', {from: userAddress}), 'CoreRef: Caller is not a PCV controller');
    });
  });

  describe('Set USD per FEI', function() {
    it('governor succeeds', async function() {
      await this.reserveStabilizer.setUsdPerFeiRate('10000', {from: governorAddress});
      expect(await this.reserveStabilizer.usdPerFeiBasisPoints()).to.be.equal(toBN('10000'));
    });

    it('non-governor reverts', async function() {
      await expectRevert(this.reserveStabilizer.setUsdPerFeiRate('10000', {from: userAddress}), 'CoreRef: Caller is not a governor');
    });

    it('too high usd per fei reverts', async function() {
      await expectRevert(this.reserveStabilizer.setUsdPerFeiRate('10001', {from: governorAddress}), 'ReserveStabilizer: Exceeds bp granularity');
    });
  });
});

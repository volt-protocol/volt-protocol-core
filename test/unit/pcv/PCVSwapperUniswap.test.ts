import hre, { ethers, artifacts } from 'hardhat';
import { expect } from 'chai'
import { time, expectRevert, expectEvent, getAddresses, getCore } from '../../helpers';
import { Signer } from 'ethers'
import { HardhatNetworkConfig } from 'hardhat/types';

const PCVSwapperUniswap = artifacts.readArtifactSync('PCVSwapperUniswap');
const ChainlinkOracleWrapper = artifacts.readArtifactSync('ChainlinkOracleWrapper');
const Fei = artifacts.readArtifactSync('Fei');
const MockOracle = artifacts.readArtifactSync('MockOracle');
const MockWeth = artifacts.readArtifactSync('MockWeth');
const MockPair = artifacts.readArtifactSync('MockUniswapV2PairLiquidity');
const MockChainlinkOracle = artifacts.readArtifactSync('MockChainlinkOracle');

const e18 = '000000000000000000';

const toBN = ethers.BigNumber.from

describe('PCVSwapperUniswap', function () {
  let userAddress: string
  let secondUserAddress: string
  let minterAddress: string
  let guardianAddress: string
  let governorAddress: string
  let pcvControllerAddress: string

  // eslint-disable-next-line consistent-return
  this.beforeAll(async function() {
    // Can only get the current price on a forked network (since we haven't deployed Uniswap stuff in test setup)
    if (!((hre.network.config) as HardhatNetworkConfig).forking) {
      return this.skip();
    }

    return undefined;
  });

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
      secondUserAddress,
      minterAddress,
      guardianAddress,
      governorAddress,
      pcvControllerAddress
    } = await getAddresses());

    this.core = await getCore();
    this.weth = await ethers.getContractAt('MockWeth', '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2');
    this.fei = await ethers.getContractAt('Fei', await this.core.fei());
    this.pair = await (await ethers.getContractFactory('MockPair')).deploy(this.fei.address, this.weth.address);
    await this.pair.setReserves(`62500000${e18}`, `25000${e18}`);
    // await web3.eth.sendTransaction({from: userAddress, to: this.pair.address, value: '25000'+e18});
    await this.fei.mint(this.pair.address, `62500000${e18}`, {from: minterAddress});
    this.oracle = await (await ethers.getContractFactory('MockOracle')).deploy(2500); // 2500:1 oracle price
    this.mockChainlinkOracle = await (await ethers.getContractFactory('MockChainlinkOracle')).deploy('500', 0); // 0 decimals, val = 500
    this.chainlinkOracleWrapper = await (await ethers.getContractFactory('ChainlinkOracleWrapper')).deploy(this.core.address, this.mockChainlinkOracle.address);

    this.swapper = await (await ethers.getContractFactory('PCVSwapperUniswap')).deploy(
      {
        _core: this.core.address,
        _oracle: this.oracle.address, // oracle
        _backupOracle: this.oracle.address, // backup oracle
        _invertOraclePrice: false,
        _decimalsNormalizer: 0,
      }, 
      {
        _tokenSpent: this.weth.address,
        _tokenReceived: this.fei.address,
        _tokenReceivingAddress: userAddress,
        _maxSpentPerSwap: `100${e18}`,
        _maximumSlippageBasisPoints: '300',
        _pair: this.pair.address,

      },
      {
        _swapFrequency: '1000',
        _swapIncentiveAmount: `200${e18}` // swap incentive = 200 FEI
      }       
    );

    await this.core.grantPCVController(pcvControllerAddress, {from: governorAddress});
  });

  describe('Payable', function() {
    it('should accept ETH transfers', async function() {
      // send 23 ETH
      await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `23${e18}`});
      expect(await ethers.provider.getBalance(this.swapper.address)).to.be.equal(`23${e18}`);
    });
  });

  describe('IPCVDeposit interface override', function() {
    describe('Getters', function() {
      it('balance()', async function() {
        await this.fei.mint(this.swapper.address, '1000', {from: minterAddress});
        expect(await this.swapper.balance()).to.be.equal('1000');
      });
    });
    describe('Withdraw', function() {
      describe('As PCVController', function() {
        it('withdraw() emit WithdrawERC20', async function() {
          expect(await this.fei.balanceOf(this.swapper.address)).to.be.equal('0');
          expect(await this.fei.balanceOf(userAddress)).to.be.equal('0');
          await this.fei.mint(this.swapper.address, `1${e18}`, {from: minterAddress});
          expect(await this.fei.balanceOf(this.swapper.address)).to.be.equal(`1${e18}`);
          await expectEvent(
            await this.swapper.withdraw(userAddress, `1${e18}`, {from: pcvControllerAddress}),
            'WithdrawERC20',
            {
              _caller: pcvControllerAddress,
              _to: userAddress,
              _token: this.fei.address,
              _amount: `1${e18}`
            }
          );
          expect(await this.fei.balanceOf(this.swapper.address)).to.be.equal('0');
          expect(await this.fei.balanceOf(userAddress)).to.be.equal(`1${e18}`);
        });
      });
      describe('As Anyone', function() {
        it('revert withdraw() onlyPCVController', async function() {
          await expectRevert(
            this.swapper.withdraw(userAddress, 1),
            'CoreRef: Caller is not a PCV controller'
          );
        });
      });
    });
    describe('Deposit', function() {
      it('Wraps ETH', async function() {
        await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `100${e18}`});
        await this.swapper.deposit();
        expect(await ethers.provider.getBalance(this.swapper.address)).to.be.equal('0');
        expect(await this.weth.balanceOf(this.swapper.address)).to.be.equal(`100${e18}`);
      });
    });
  });
  describe('IPCVSwapper interface override', function() {
    describe('Getters', function() {
      it('tokenSpent()', async function() {
        expect(await this.swapper.tokenSpent()).to.equal(this.weth.address);
      });
      it('tokenReceived()', async function() {
        expect(await this.swapper.tokenReceived()).to.equal(this.fei.address);
      });
      it('tokenReceivingAddress()', async function() {
        expect(await this.swapper.tokenReceivingAddress()).to.equal(userAddress);
      });
    });
    describe('Setters', function() {
      describe('As Governor', function() {
        it('setReceivingAddress() emit UpdateReceivingAddress', async function() {
          expect(await this.swapper.tokenReceivingAddress()).to.equal(userAddress);
          await expectEvent(
            await this.swapper.setReceivingAddress(secondUserAddress, {from: governorAddress}),
            'UpdateReceivingAddress',
            { newTokenReceivingAddress: secondUserAddress }
          );
          expect(await this.swapper.tokenReceivingAddress()).to.equal(secondUserAddress);
        });
      });
      describe('As Anyone', function() {
        it('revert setReceivingAddress() onlyGovernor', async function() {
          await expectRevert(
            this.swapper.setReceivingAddress(userAddress),
            'CoreRef: Caller is not a governor'
          );
        });
      });
    });
    describe('Withdraw', function() {
      describe('As PCVController', function() {
        it('withdrawETH() emit WithdrawETH', async function() {
          await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `10${e18}`});
          await this.swapper.wrapETH();
          const balanceBefore = toBN(await ethers.provider.getBalance(secondUserAddress));
          await expectEvent(
            await this.swapper.withdrawETH(secondUserAddress, `10${e18}`, {from: pcvControllerAddress}),
            'WithdrawETH',
            {
              _caller: pcvControllerAddress,
              _to: secondUserAddress,
              _amount: `10${e18}`
            }
          );
          expect(await ethers.provider.getBalance(secondUserAddress)).to.be.equal(toBN(`10${e18}`).add(balanceBefore));
        });
        it('withdrawETH() revert if not enough WETH to unwrap', async function() {
          await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `10${e18}`});
          await this.swapper.wrapETH();
          await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `20${e18}`});
          // revert because the swapper has 10 WETH and 20 ETH, can't unwrap 15 WETH
          // to solve this situation, swapper.wrapETH() should be called before withdraw.
          await expectRevert(
            this.swapper.withdrawETH(userAddress, `15${e18}`, {from: pcvControllerAddress}),
            'revert'
          );
        });
        it('withdrawERC20() emit WithdrawERC20', async function() {
          expect(await this.fei.balanceOf(this.swapper.address)).to.be.equal('0');
          expect(await this.fei.balanceOf(userAddress)).to.be.equal('0');
          await this.fei.mint(this.swapper.address, `1${e18}`, {from: minterAddress});
          expect(await this.fei.balanceOf(this.swapper.address)).to.be.equal(`1${e18}`);
          await expectEvent(
            await this.swapper.withdrawERC20(this.fei.address, userAddress, `1${e18}`, {from: pcvControllerAddress}),
            'WithdrawERC20',
            {
              _caller: pcvControllerAddress,
              _to: userAddress,
              _token: this.fei.address,
              _amount: `1${e18}`
            }
          );
          expect(await this.fei.balanceOf(this.swapper.address)).to.be.equal('0');
          expect(await this.fei.balanceOf(userAddress)).to.be.equal(`1${e18}`);
        });
      });
      describe('As Anyone', function() {
        it('revert withdrawETH() onlyPCVController', async function() {
          await expectRevert(
            this.swapper.withdrawETH(userAddress, 1),
            'CoreRef: Caller is not a PCV controller'
          );
        });
        it('revert withdrawERC20() onlyPCVController', async function() {
          await expectRevert(
            this.swapper.withdrawERC20(userAddress, '0x6B175474E89094C44Da98b954EedeAC495271d0F', 1),
            'CoreRef: Caller is not a PCV controller'
          );
        });
      });
    });
    describe('Swap', function() {
      it('swap() emit Swap', async function() {
        await time.increase('1000');
        await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `100${e18}`});
        await this.swapper.wrapETH({ from: pcvControllerAddress });
        await expectEvent(
          await this.swapper.swap({from: userAddress}),
          'Swap',
          {
            _caller: userAddress,
            _tokenSpent: this.weth.address,
            _tokenReceived: this.fei.address,
            _amountSpent: `100${e18}`,
            _amountReceived: '248259939361825041733566' // not exactly 250000e18 because of slippage & fees
          }
        );
      });
    });
  });

  describe('Setters', function() {
    it('setMaximumSlippage() revert if not governor', async function() {
      await expectRevert(
        this.swapper.setMaximumSlippage('500'),
        'CoreRef: Caller is not a governor'
      );
    });
    it('setMaximumSlippage() revert on invalid value', async function() {
      await expectRevert(
        this.swapper.setMaximumSlippage('10001', { from: governorAddress }),
        'PCVSwapperUniswap: Exceeds bp granularity.'
      );
    });
    it('setMaximumSlippage() emit UpdateMaximumSlippage', async function() {
      expect(await this.swapper.maximumSlippageBasisPoints()).to.be.equal('300');
      await expectEvent(
        await this.swapper.setMaximumSlippage('500', { from: governorAddress }),
        'UpdateMaximumSlippage',
        {
          newMaximumSlippage: '500'
        }
      );
      expect(await this.swapper.maximumSlippageBasisPoints()).to.be.equal('500');
    });
    it('setMaxSpentPerSwap() revert if not governor', async function() {
      await expectRevert(
        this.swapper.setMaxSpentPerSwap('0'),
        'CoreRef: Caller is not a governor'
      );
    });
    it('setMaxSpentPerSwap() revert on invalid value', async function() {
      await expectRevert(
        this.swapper.setMaxSpentPerSwap('0', { from: governorAddress }),
        'PCVSwapperUniswap: Cannot swap 0.'
      );
    });
    it('setMaxSpentPerSwap() emit UpdateMaxSpentPerSwap', async function() {
      expect(await this.swapper.maxSpentPerSwap()).to.be.equal(`100${e18}`);
      await expectEvent(
        await this.swapper.setMaxSpentPerSwap(`50${e18}`, { from: governorAddress }),
        'UpdateMaxSpentPerSwap',
        {
          newMaxSpentPerSwap: `50${e18}`
        }
      );
      expect(await this.swapper.maxSpentPerSwap()).to.be.equal(`50${e18}`);
    });
    it('setSwapFrequency() revert if not governor', async function() {
      await expectRevert(
        this.swapper.setSwapFrequency('2000'),
        'CoreRef: Caller is not a governor'
      );
    });
    it('setSwapFrequency() emit UpdateSwapFrequency', async function() {
      expect(await this.swapper.duration()).to.be.equal('1000');
      await expectEvent(
        await this.swapper.setSwapFrequency('2000', { from: governorAddress }),
        'DurationUpdate',
        {
          oldDuration: '1000',
          newDuration: '2000'
        }
      );
      expect(await this.swapper.duration()).to.be.equal('2000');
    });
  });

  describe('ETH wrap/unwrap', function() {
    it('wrapETH()', async function() {
      expect(await this.weth.balanceOf(this.swapper.address)).to.be.equal(`0${e18}`);
      await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `100${e18}`});
      expect(await ethers.provider.getBalance(this.swapper.address)).to.be.equal(`100${e18}`);
      await this.swapper.wrapETH();
      expect(await this.weth.balanceOf(this.swapper.address)).to.be.equal(`100${e18}`);
      expect(await ethers.provider.getBalance(this.swapper.address)).to.be.equal(`0${e18}`);
    });
  });

  describe('Swap', function() {
    it('revert if paused by guardian', async function() {
      await time.increase('1000');
      await this.swapper.pause({from: guardianAddress});
      await expectRevert(this.swapper.swap(), 'Pausable: paused');
    });
    it('revert if paused by governor', async function() {
      await time.increase('1000');
      await this.swapper.pause({from: governorAddress});
      await expectRevert(this.swapper.swap(), 'Pausable: paused');
    });
    it('revert if time is not elapsed', async function() {
      await expectRevert(this.swapper.swap(), 'Timed: time not ended');
    });
    it('revert if oracle is invalid', async function() {
      await this.oracle.setValid(false);
      await time.increase('1000');
      await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `100${e18}`});
      await this.swapper.wrapETH({ from: pcvControllerAddress });
      await expectRevert(this.swapper.swap(), 'OracleRef: oracle invalid');
    });
    it('revert if slippage is too high', async function() {
      await time.increase('1000');
      await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `1000${e18}`});
      await this.swapper.wrapETH({ from: pcvControllerAddress });
      await this.swapper.setMaxSpentPerSwap(`1000${e18}`, {from: governorAddress});
      await expectRevert(this.swapper.swap(), 'PCVSwapperUniswap: slippage too high.');
    });
    it('send tokens to tokenReceivingAddress', async function() {
      await time.increase('1000');
      await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `100${e18}`});
      await this.swapper.wrapETH({ from: pcvControllerAddress });
      await this.swapper.swap({from: userAddress});
      expect(await this.fei.balanceOf(userAddress)).to.be.equal('248259939361825041733566');
    });
    it('swap remaining tokens if balance < maxSpentPerSwap', async function() {
      await time.increase('1000');
      await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `50${e18}`});
      await this.swapper.wrapETH({ from: pcvControllerAddress });
      await this.swapper.swap({from: userAddress});
      expect(await this.fei.balanceOf(userAddress)).to.be.equal('124376992277398866659880');
    });
    it('no FEI incentive to caller if swapper is not a Minter', async function() {
      await time.increase('1000');
      await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `50${e18}`});
      await this.swapper.wrapETH({ from: pcvControllerAddress });
      expect((await this.fei.balanceOf(secondUserAddress)) / 1e18).to.be.equal(0);
      await this.swapper.swap({from: secondUserAddress});
      expect((await this.fei.balanceOf(secondUserAddress)) / 1e18).to.be.equal(0);
    });
    it('send FEI incentive to caller if swapper is Minter', async function() {
      await time.increase('1000');
      await impersonatedSigners[userAddress].sendTransaction({from: userAddress, to: this.swapper.address, value: `50${e18}`});
      await this.swapper.wrapETH({ from: pcvControllerAddress });
      await this.core.grantMinter(this.swapper.address, {from: governorAddress});
      expect((await this.fei.balanceOf(secondUserAddress)) / 1e18).to.be.equal(0);
      await this.swapper.swap({from: secondUserAddress});
      expect((await this.fei.balanceOf(secondUserAddress)) / 1e18).to.be.equal(200);
    });
  });
});

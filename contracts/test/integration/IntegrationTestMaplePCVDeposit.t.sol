//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {Core} from "../../core/Core.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {IMaplePool} from "../../pcv/maple/IMaplePool.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {IDSSPSM} from "../../pcv/maker/IDSSPSM.sol";
import {Constants} from "../../Constants.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {IMapleRewards} from "../../pcv/maple/IMapleRewards.sol";
import {MaplePCVDeposit} from "../../pcv/maple/MaplePCVDeposit.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";

interface IMapleLoanFactory {
    function createInstance(bytes calldata, bytes32) external returns (address);
}

interface IMapleLoan {
    function drawdownFunds(uint256 amt, address to)
        external
        returns (uint256 collateralPosted);

    function makePayment(uint256 amt)
        external
        returns (uint256 principal, uint256 interest);

    function paymentsRemaining() external view returns (uint256);

    function nextPaymentDueDate() external view returns (uint256);

    function gracePeriod() external view returns (uint256);
}

contract IntegrationTestMaplePCVDeposit is DSTest {
    using SafeCast for *;

    event Deposit(address indexed _caller, uint256 _amount);
    event Withdrawal(
        address indexed _caller,
        address indexed _to,
        uint256 _amount
    );
    event Harvest(address indexed _token, int256 _profit, uint256 _timestamp);
    event DefaultSuffered(
        address indexed loan,
        uint256 defaultSuffered,
        uint256 bptsBurned,
        uint256 bptsReturned,
        uint256 liquidityAssetRecoveredFromBurn
    );

    Vm public constant vm = Vm(HEVM_ADDRESS);

    MaplePCVDeposit private usdcDeposit;

    PCVGuardian private immutable pcvGuardian =
        PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    Core private core = Core(MainnetAddresses.CORE);

    IERC20 private usdc = IERC20(MainnetAddresses.USDC);

    uint256 public constant targetUsdcBalance = 100_000e6;

    /// Maple Parameters for creating loans
    address private constant mapleLoanFactory =
        0x36a7350309B2Eb30F3B908aB0154851B5ED81db0;
    address private constant mapleDebtLockerFactory =
        0xA83404CAA79989FfF1d84bA883a1b8187397866C;
    uint256 private constant gracePeriod = 432000; // 5 days

    /// @notice once you signal to withdraw after lockup, wait 10 days
    uint256 public constant cooldownPeriod = 864000;

    /// @notice once you have waited for cool down period to pass
    /// you have 2 days to withdraw before you have to request to withdraw again
    uint256 public constant withdrawPeriod = 172800;

    IERC20 public immutable mapleToken = IERC20(MainnetAddresses.MPL_TOKEN);
    address public immutable mapleOwner =
        MainnetAddresses.MPL_GOVERNOR_MULTISIG;
    address public immutable maplePool = MainnetAddresses.MPL_ORTHOGONAL_POOL;
    address public immutable mapleRewards =
        MainnetAddresses.MPL_ORTHOGONAL_REWARDS;

    function setUp() public {
        usdcDeposit = new MaplePCVDeposit(
            address(core),
            maplePool,
            mapleRewards,
            address(0)
        );

        vm.label(address(usdcDeposit), "Maple USDC PCV Deposit");
        vm.label(address(usdc), "USDC Token");
        vm.label(address(maplePool), "Maple Pool");
        vm.label(address(mapleRewards), "Maple Rewards");

        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        usdc.transfer(address(usdcDeposit), targetUsdcBalance);

        /// governor has pcv controller role
        vm.prank(MainnetAddresses.GOVERNOR);
        // check Deposit event
        vm.expectEmit(true, false, false, true, address(usdcDeposit));
        emit Deposit(MainnetAddresses.GOVERNOR, targetUsdcBalance);
        // do initial deposit
        usdcDeposit.deposit();
    }

    function testSetup() public {
        assertEq(address(usdcDeposit.core()), address(core));
        assertEq(usdcDeposit.balanceReportedIn(), address(usdc));
        assertEq(usdcDeposit.maplePool(), maplePool);
        assertEq(usdcDeposit.mapleRewards(), mapleRewards);
        assertEq(usdcDeposit.mapleToken(), MainnetAddresses.MPL_TOKEN);
        assertEq(usdcDeposit.balance(), targetUsdcBalance);
        assertEq(usdcDeposit.lastRecordedBalance(), targetUsdcBalance);
    }

    function testWithdraw() public {
        uint256 rewardRate = IMapleRewards(mapleRewards).rewardRate();
        vm.prank(mapleOwner);
        IMapleRewards(mapleRewards).notifyRewardAmount(rewardRate);

        vm.warp(block.timestamp + IMaplePool(maplePool).lockupPeriod());
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();

        vm.warp(block.timestamp + cooldownPeriod);

        /// governor has pcv controller role
        vm.prank(MainnetAddresses.GOVERNOR);
        // check Harvest event for MPL rewards (don't check amount)
        vm.expectEmit(true, false, false, false, address(usdcDeposit));
        emit Harvest(MainnetAddresses.MPL_TOKEN, 12345, block.timestamp);
        // check Harvest event for USDC interests (no interests/losses)
        vm.expectEmit(true, false, false, true, address(usdcDeposit));
        emit Harvest(MainnetAddresses.USDC, 0, block.timestamp);
        // check Withdrawal event for principal
        vm.expectEmit(true, true, false, true, address(usdcDeposit));
        emit Withdrawal(
            MainnetAddresses.GOVERNOR,
            address(this),
            targetUsdcBalance
        );
        // do withdraw
        usdcDeposit.withdraw(address(this), targetUsdcBalance);

        assertEq(usdcDeposit.balance(), 0);
        assertEq(usdcDeposit.lastRecordedBalance(), 0);
        assertEq(usdc.balanceOf(address(this)), targetUsdcBalance);
        assertTrue(mapleToken.balanceOf(address(usdcDeposit)) > 0);
    }

    function testHarvestFailIfPaused() public {
        // Pause contract
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.pause();

        vm.expectRevert(bytes("Pausable: paused"));
        usdcDeposit.harvest();
    }

    function testHarvest() public {
        uint256 rewardRate = IMapleRewards(mapleRewards).rewardRate();
        vm.prank(mapleOwner);
        IMapleRewards(mapleRewards).notifyRewardAmount(rewardRate);

        vm.warp(block.timestamp + IMaplePool(maplePool).lockupPeriod());

        // check Harvest event for MPL rewards (don't check amount)
        vm.expectEmit(true, false, false, false, address(usdcDeposit));
        emit Harvest(MainnetAddresses.MPL_TOKEN, 12345, block.timestamp);
        usdcDeposit.harvest();

        uint256 mplBalance = mapleToken.balanceOf(address(usdcDeposit));

        assertTrue(mplBalance != 0);
    }

    function testAccrueFailIfPaused() public {
        // Pause contract
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.pause();

        vm.expectRevert(bytes("Pausable: paused"));
        usdcDeposit.accrue();
    }

    function testAccrueInterestsEarned() public {
        assertEq(usdcDeposit.lastRecordedBalance(), targetUsdcBalance);

        // Someone creates a loan (180 days payment interval)
        address mapleLoan = _createAndFundMapleLoan(
            15552000,
            targetUsdcBalance
        );

        // Send more USDC to the borrower so they can pay interests
        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        usdc.transfer(address(this), targetUsdcBalance);

        // Warp forward and make payment
        vm.warp(block.timestamp + gracePeriod + 15552000);
        usdc.approve(mapleLoan, type(uint256).max);
        (uint256 principal1, uint256 interest1) = IMapleLoan(mapleLoan)
            .makePayment(7_000e6);
        assertEq(principal1, 0);
        assertTrue(interest1 > 5_900e6);

        // Pool Manager claims the interests
        vm.prank(MainnetAddresses.MPL_ORTHOGONAL_POOL_DELEGATE);
        IMaplePool(maplePool).claim(mapleLoan, mapleDebtLockerFactory);

        // Accrue interests in PCVDeposit and check live+recorded balances
        uint256 protocolEarnedInterests = usdcDeposit.balance() -
            usdcDeposit.lastRecordedBalance();
        assertTrue(protocolEarnedInterests > 1e6); // ast least 1 USDC of interests

        // check Harvest event for USDC interests
        vm.expectEmit(true, false, false, true, address(usdcDeposit));
        emit Harvest(
            MainnetAddresses.USDC,
            int256(protocolEarnedInterests),
            block.timestamp
        );
        usdcDeposit.accrue();

        assertEq(
            usdcDeposit.lastRecordedBalance(),
            targetUsdcBalance + protocolEarnedInterests
        );
        assertEq(usdcDeposit.lastRecordedBalance(), usdcDeposit.balance());
    }

    function testAccrueLossesIncurredButCovered() public {
        assertEq(usdcDeposit.lastRecordedBalance(), targetUsdcBalance);

        // Someone creates a loan (30 days payment interval)
        address mapleLoan = _createAndFundMapleLoan(2592000, targetUsdcBalance);

        assertEq(
            IMapleLoan(mapleLoan).nextPaymentDueDate(),
            block.timestamp + 2592000
        );
        assertEq(IMapleLoan(mapleLoan).gracePeriod(), gracePeriod);

        // Pool Manager triggers a loan default
        vm.warp(block.timestamp + gracePeriod + 2592000 + 1000);
        vm.prank(MainnetAddresses.MPL_ORTHOGONAL_POOL_DELEGATE);
        IMaplePool(maplePool).triggerDefault(mapleLoan, mapleDebtLockerFactory);

        // Pool Manager claims to update accounting
        vm.prank(MainnetAddresses.MPL_ORTHOGONAL_POOL_DELEGATE);
        vm.expectEmit(true, false, false, false, maplePool);
        emit DefaultSuffered(mapleLoan, 123, 456, 789, 101);
        IMaplePool(maplePool).claim(mapleLoan, mapleDebtLockerFactory);

        // First-loss capital absorbed the default
        assertEq(usdcDeposit.balance(), targetUsdcBalance);

        // The PCV Deposit can properly withdraw all principal
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();
        vm.warp(block.timestamp + cooldownPeriod);
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdraw(address(this), targetUsdcBalance);
        assertEq(usdcDeposit.balance(), 0);
        assertEq(usdc.balanceOf(address(this)), 2 * targetUsdcBalance); // 1 from the drawn loan & 1 from the withdraw
    }

    function testAccrueLossesIncurredNotCovered() public {
        // Load the PCV Deposit with a large amount
        uint256 largeUsdcBalance = 20_000_000e6; // 20M$
        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        usdc.transfer(
            address(usdcDeposit),
            largeUsdcBalance - targetUsdcBalance
        );
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.deposit();
        assertEq(usdcDeposit.lastRecordedBalance(), largeUsdcBalance);

        // Someone creates a loan (30 days payment interval)
        address mapleLoan = _createAndFundMapleLoan(2592000, largeUsdcBalance);

        assertEq(
            IMapleLoan(mapleLoan).nextPaymentDueDate(),
            block.timestamp + 2592000
        );
        assertEq(IMapleLoan(mapleLoan).gracePeriod(), gracePeriod);

        // Pool Manager triggers a loan default
        vm.warp(block.timestamp + gracePeriod + 2592000 + 1000);
        vm.prank(MainnetAddresses.MPL_ORTHOGONAL_POOL_DELEGATE);
        IMaplePool(maplePool).triggerDefault(mapleLoan, mapleDebtLockerFactory);

        // Pool Manager claims to update accounting
        vm.prank(MainnetAddresses.MPL_ORTHOGONAL_POOL_DELEGATE);
        vm.expectEmit(true, false, false, false, maplePool);
        emit DefaultSuffered(mapleLoan, 123, 456, 789, 101);
        IMaplePool(maplePool).claim(mapleLoan, mapleDebtLockerFactory);

        // The PCV Deposit incurred a loss
        uint256 pcvLoss = largeUsdcBalance - usdcDeposit.balance();
        assertEq(usdcDeposit.lastRecordedBalance(), largeUsdcBalance);
        assertTrue(pcvLoss > 1_000_000e6); // loss is 4.7M$ as of 2022-11-04 but pool cover could change over time

        // check Harvest event for USDC interests
        vm.expectEmit(true, false, false, true, address(usdcDeposit));
        emit Harvest(
            MainnetAddresses.USDC,
            -1 * int256(pcvLoss),
            block.timestamp
        );
        usdcDeposit.accrue();

        assertEq(usdcDeposit.lastRecordedBalance(), largeUsdcBalance - pcvLoss);
        assertEq(usdcDeposit.balance(), largeUsdcBalance - pcvLoss);
    }

    function testLossesIncurredAndDepositAgain() public {
        // Load the PCV Deposit with a large amount
        uint256 largeUsdcBalance = 20_000_000e6; // 20M$
        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        usdc.transfer(
            address(usdcDeposit),
            largeUsdcBalance - targetUsdcBalance
        );
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.deposit();
        assertEq(usdcDeposit.lastRecordedBalance(), largeUsdcBalance);

        // Someone creates a loan (30 days payment interval)
        address mapleLoan = _createAndFundMapleLoan(2592000, largeUsdcBalance);

        assertEq(
            IMapleLoan(mapleLoan).nextPaymentDueDate(),
            block.timestamp + 2592000
        );
        assertEq(IMapleLoan(mapleLoan).gracePeriod(), gracePeriod);

        // Pool Manager triggers a loan default
        vm.warp(block.timestamp + gracePeriod + 2592000 + 1000);
        vm.prank(MainnetAddresses.MPL_ORTHOGONAL_POOL_DELEGATE);
        IMaplePool(maplePool).triggerDefault(mapleLoan, mapleDebtLockerFactory);

        // Pool Manager claims to update accounting
        vm.prank(MainnetAddresses.MPL_ORTHOGONAL_POOL_DELEGATE);
        vm.expectEmit(true, false, false, false, maplePool);
        emit DefaultSuffered(mapleLoan, 123, 456, 789, 101);
        IMaplePool(maplePool).claim(mapleLoan, mapleDebtLockerFactory);

        // The PCV Deposit incurred a loss
        uint256 pcvLoss = largeUsdcBalance - usdcDeposit.balance();
        assertEq(usdcDeposit.lastRecordedBalance(), largeUsdcBalance);
        assertTrue(pcvLoss > 1_000_000e6); // loss is 4.7M$ as of 2022-11-04 but pool cover could change over time

        // check Harvest event for USDC interests
        vm.expectEmit(true, false, false, true, address(usdcDeposit));
        emit Harvest(
            MainnetAddresses.USDC,
            -1 * int256(pcvLoss),
            block.timestamp
        );
        usdcDeposit.accrue();

        assertEq(usdcDeposit.lastRecordedBalance(), largeUsdcBalance - pcvLoss);
        assertEq(usdcDeposit.balance(), largeUsdcBalance - pcvLoss);

        // Make another deposit
        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        usdc.transfer(address(usdcDeposit), largeUsdcBalance);
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.deposit();
        assertEq(
            usdcDeposit.lastRecordedBalance(),
            largeUsdcBalance * 2 - pcvLoss
        );
        assertEq(usdcDeposit.balance(), largeUsdcBalance * 2 - pcvLoss);
    }

    function _testWithdraw(uint256 amount) private {
        _setRewardsAndWarp();
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();

        vm.warp(block.timestamp + cooldownPeriod);

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdraw(address(this), amount);

        uint256 mplBalance = mapleToken.balanceOf(address(usdcDeposit));

        uint256 targetBal = targetUsdcBalance - amount;
        assertEq(usdcDeposit.balance(), targetBal);
        assertEq(usdc.balanceOf(address(this)), amount);
        assertTrue(mplBalance != 0);
    }

    function testWithdrawAtCoolDownEnd() public {
        _testWithdraw(targetUsdcBalance);
    }

    function testWithdrawAtCoolDownEndFuzz(uint40 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount <= targetUsdcBalance);
        _testWithdraw(amount);
    }

    function testSignalWithdrawPCVControllerSucceeds() public {
        uint256 blockTimestamp = 10_000;

        vm.warp(blockTimestamp);
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();

        assertEq(
            IMaplePool(maplePool).withdrawCooldown(address(usdcDeposit)),
            blockTimestamp
        );
    }

    function testCancelWithdrawPCVControllerSucceeds() public {
        uint256 blockTimestamp = 10_000;

        vm.warp(blockTimestamp);
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();

        assertEq(
            IMaplePool(maplePool).withdrawCooldown(address(usdcDeposit)),
            blockTimestamp
        );

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.cancelWithdraw();

        assertEq(
            IMaplePool(maplePool).withdrawCooldown(address(usdcDeposit)),
            0
        );
    }

    function testExitRewardsPCVControllerSucceeds() public {
        _setRewardsAndWarp();

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.exitRewards();

        assertEq(
            IMaplePool(maplePool).custodyAllowance(
                address(usdcDeposit),
                address(mapleRewards)
            ),
            0
        );
        assertEq(
            IMapleRewards(mapleRewards).balanceOf(address(usdcDeposit)),
            0
        );
    }

    function testWithdrawFromRewardsContractPCVControllerSucceeds() public {
        _setRewardsAndWarp();

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdrawFromRewardsContract();

        assertEq(
            IMaplePool(maplePool).custodyAllowance(
                address(usdcDeposit),
                address(mapleRewards)
            ),
            0
        );
        assertEq(
            IMapleRewards(mapleRewards).balanceOf(address(usdcDeposit)),
            0
        );
    }

    function testWithdrawFromRewardsContractAndWithdrawFromPoolPCVControllerSucceeds()
        public
    {
        testWithdrawFromRewardsContractPCVControllerSucceeds();

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();

        vm.warp(block.timestamp + cooldownPeriod);

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdrawFromPool(address(this), targetUsdcBalance);
    }

    function testExitRewardsContractAndWithdrawFromPoolPCVControllerSucceeds()
        public
    {
        _setRewardsAndWarp();

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.exitRewards();

        assertEq(
            IMaplePool(maplePool).custodyAllowance(
                address(usdcDeposit),
                address(mapleRewards)
            ),
            0
        );
        assertEq(
            IMapleRewards(mapleRewards).balanceOf(address(usdcDeposit)),
            0
        );

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();
        vm.warp(block.timestamp + cooldownPeriod);

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdrawFromPool(address(this), targetUsdcBalance);
    }

    function testGovernorEmergencyActionExitSucceeds() public {
        _setRewardsAndWarp();

        MaplePCVDeposit.Call[] memory calls = new MaplePCVDeposit.Call[](1);
        calls[0].callData = abi.encodeWithSignature("exit()");
        calls[0].target = mapleRewards;

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.emergencyAction(calls);

        assertEq(
            IMaplePool(maplePool).custodyAllowance(
                address(usdcDeposit),
                address(mapleRewards)
            ),
            0
        );
        assertEq(
            IMapleRewards(mapleRewards).balanceOf(address(usdcDeposit)),
            0
        );
    }

    function testDepositNotPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.deposit();
    }

    function testSignalWithdrawNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.signalIntentToWithdraw();
    }

    function testCancelWithdrawNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.cancelWithdraw();
    }

    function testWithdrawNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdraw(address(this), targetUsdcBalance);
    }

    function testwithdrawFromPoolNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdrawFromPool(address(this), targetUsdcBalance);
    }

    function testWithdrawFromRewardsContractgNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdrawFromRewardsContract();
    }

    function testExitRewardsPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.exitRewards();
    }

    function testEmergencyActionNonPCVControllerFails() public {
        MaplePCVDeposit.Call[] memory calls = new MaplePCVDeposit.Call[](2);

        vm.expectRevert("CoreRef: Caller is not a governor");
        usdcDeposit.emergencyAction(calls);
    }

    function _setRewardsAndWarp() private {
        uint256 rewardRate = IMapleRewards(mapleRewards).rewardRate();
        vm.prank(mapleOwner);
        IMapleRewards(mapleRewards).notifyRewardAmount(rewardRate);

        vm.warp(
            block.timestamp +
                IMaplePool(maplePool).lockupPeriod() -
                cooldownPeriod
        );
    }

    /// @notice Create a Maple Loan and impersonate the pool delegate to fund it.
    /// The borrower will also drawdown the funds from the funded loan.
    function _createAndFundMapleLoan(
        uint256 paymentInterval,
        uint256 principalRequested
    ) private returns (address mapleLoan) {
        bytes memory arguments = abi.encode(
            address(this), // borrower
            address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599), // assets[0] = collateral = WBTC
            MainnetAddresses.USDC, // assets[1] = principal = USDC
            gracePeriod, // terms[0]
            paymentInterval, // terms[1] = paymentInterval
            2, // terms[2] = numberOfPayments
            0, // amounts[0] = collateralRequired
            principalRequested, // amounts[1] = principalRequested
            principalRequested, // amounts[2] = endingPrincipal
            0.12e18, // rates[0] = interestRate = 12%
            0.02e18, // rates[1] = earlyFeeRate = 2%
            0, // rates[2] = lateFeeRate = 0
            0.05e18 // rates[3] = lateInterestPremium = 5%
        );
        mapleLoan = IMapleLoanFactory(mapleLoanFactory).createInstance(
            arguments,
            keccak256(bytes("some salt"))
        );
        vm.label(mapleLoan, "mapleLoan");

        // Pool delegate funds the loan
        // The pool has enough cash to fund the loan because the PCVDeposit
        // did a deposit() in the setUp() step.
        vm.prank(MainnetAddresses.MPL_ORTHOGONAL_POOL_DELEGATE);
        IMaplePool(maplePool).fundLoan(
            mapleLoan,
            mapleDebtLockerFactory,
            principalRequested
        );

        // Borrower pulls loan amount
        assertEq(usdc.balanceOf(address(this)), 0);
        IMapleLoan(mapleLoan).drawdownFunds(principalRequested, address(this));
        assertEq(usdc.balanceOf(address(this)), principalRequested);
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {Core} from "../../core/Core.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {IPool} from "../../pcv/maple/IPool.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {IDSSPSM} from "../../pcv/maker/IDSSPSM.sol";
import {Constants} from "../../Constants.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {IMplRewards} from "../../pcv/maple/IMplRewards.sol";
import {MockMaplePool} from "../../mock/MockMaplePool.sol";
import {MaplePCVDeposit} from "../../pcv/maple/MaplePCVDeposit.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";

import "hardhat/console.sol";

contract IntegrationTestMaplePCVDeposit is DSTest {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    MaplePCVDeposit private usdcDeposit;

    PCVGuardian private immutable pcvGuardian =
        PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    Core private core = Core(MainnetAddresses.CORE);

    IERC20 private usdc = IERC20(MainnetAddresses.USDC);

    uint256 public constant targetUsdcBalance = 100_000e6;

    /// @notice once you signal to withdraw after lockup, wait 10 days
    uint256 public constant cooldownPeriod = 864000;

    /// @notice once you have waited for cool down period to pass
    /// you have 2 days to withdraw before you have to request to withdraw again
    uint256 public constant withdrawPeriod = 172800;

    IERC20 public constant maple =
        IERC20(0x33349B282065b0284d756F0577FB39c158F935e6);
    address public constant mplRewards =
        0x7869D7a3B074b5fa484dc04798E254c9C06A5e90;
    address public constant maplePool =
        0xFeBd6F15Df3B73DC4307B1d7E65D46413e710C27;

    address public constant mapleOwner =
        0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196;

    function setUp() public {
        usdcDeposit = new MaplePCVDeposit(address(core), maplePool, mplRewards);

        vm.label(address(usdcDeposit), "Maple USDC PCV Deposit");
        vm.label(address(usdc), "USDC Token");
        vm.label(address(maplePool), "Maple Pool");
        vm.label(address(mplRewards), "Maple Rewards");

        vm.startPrank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        usdc.transfer(address(usdcDeposit), targetUsdcBalance);
        vm.stopPrank();

        /// governor has pcv controller role
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.deposit();
    }

    function testSetup() public {
        assertEq(address(usdcDeposit.core()), address(core));
        assertEq(usdcDeposit.balanceReportedIn(), address(usdc));
        assertEq(address(usdcDeposit.pool()), maplePool);
        assertEq(address(usdcDeposit.mplRewards()), mplRewards);
        assertEq(address(usdcDeposit.token()), address(MainnetAddresses.USDC));
        assertEq(usdcDeposit.balance(), targetUsdcBalance);
    }

    function testDeployFailsNotUSDCUnderlying() public {
        MockMaplePool mockPool = new MockMaplePool(address(this));

        vm.expectRevert("MaplePCVDeposit: Underlying not USDC");
        new MaplePCVDeposit(address(core), address(mockPool), mplRewards);
    }

    function testWithdraw() public {
        uint256 rewardRate = IMplRewards(mplRewards).rewardRate();
        vm.prank(mapleOwner);
        IMplRewards(mplRewards).notifyRewardAmount(rewardRate);

        vm.warp(block.timestamp + IPool(maplePool).lockupPeriod());
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();

        vm.warp(block.timestamp + cooldownPeriod);

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdraw(address(this), targetUsdcBalance);

        uint256 mplBalance = maple.balanceOf(address(usdcDeposit));

        assertEq(usdcDeposit.balance(), 0);
        assertEq(usdc.balanceOf(address(this)), targetUsdcBalance);
        assertTrue(mplBalance != 0);
    }

    function testHarvest() public {
        uint256 rewardRate = IMplRewards(mplRewards).rewardRate();
        vm.prank(mapleOwner);
        IMplRewards(mplRewards).notifyRewardAmount(rewardRate);

        vm.warp(block.timestamp + IPool(maplePool).lockupPeriod());

        usdcDeposit.harvest();

        uint256 mplBalance = maple.balanceOf(address(usdcDeposit));

        assertTrue(mplBalance != 0);
    }

    function _testWithdraw(uint256 amount) private {
        uint256 rewardRate = IMplRewards(mplRewards).rewardRate();
        vm.prank(mapleOwner);
        IMplRewards(mplRewards).notifyRewardAmount(rewardRate);

        vm.warp(
            block.timestamp + IPool(maplePool).lockupPeriod() - cooldownPeriod
        );
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();

        vm.warp(block.timestamp + cooldownPeriod);

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdraw(address(this), amount);

        uint256 mplBalance = maple.balanceOf(address(usdcDeposit));

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

    function testWithdrawAll() public {
        uint256 rewardRate = IMplRewards(mplRewards).rewardRate();
        vm.prank(mapleOwner);
        IMplRewards(mplRewards).notifyRewardAmount(rewardRate);

        vm.warp(
            block.timestamp + IPool(maplePool).lockupPeriod() - cooldownPeriod
        );
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();

        vm.warp(block.timestamp + cooldownPeriod);

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdrawAll(address(this));

        uint256 mplBalance = maple.balanceOf(address(usdcDeposit));

        assertEq(usdcDeposit.balance(), 0);
        assertEq(usdc.balanceOf(address(this)), targetUsdcBalance);
        assertTrue(mplBalance != 0);
    }

    function testSignalWithdrawPCVControllerSucceeds() public {
        uint256 blockTimestamp = 10_000;

        vm.warp(blockTimestamp);
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();

        assertEq(
            IPool(maplePool).withdrawCooldown(address(usdcDeposit)),
            blockTimestamp
        );
    }

    function testCancelWithdrawPCVControllerSucceeds() public {
        uint256 blockTimestamp = 10_000;

        vm.warp(blockTimestamp);
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.signalIntentToWithdraw();

        assertEq(
            IPool(maplePool).withdrawCooldown(address(usdcDeposit)),
            blockTimestamp
        );

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.cancelWithdraw();

        assertEq(IPool(maplePool).withdrawCooldown(address(usdcDeposit)), 0);
    }

    function testExitPCVControllerSucceeds() public {
        uint256 blockTimestamp = 10_000;

        vm.warp(blockTimestamp);

        console.log(
            "mpl rewards balance: ",
            IMplRewards(mplRewards).balanceOf(address(usdcDeposit))
        );

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.exit();

        assertEq(
            IPool(maplePool).custodyAllowance(
                address(usdcDeposit),
                address(mplRewards)
            ),
            0
        );
        assertEq(IMplRewards(mplRewards).balanceOf(address(usdcDeposit)), 0);
    }

    function testWithdrawFromRewardsContractPCVControllerSucceeds() public {
        uint256 blockTimestamp = 10_000;

        vm.warp(blockTimestamp);

        console.log(
            "mpl rewards balance: ",
            IMplRewards(mplRewards).balanceOf(address(usdcDeposit))
        );

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdrawFromRewardsContract();

        assertEq(
            IPool(maplePool).custodyAllowance(
                address(usdcDeposit),
                address(mplRewards)
            ),
            0
        );
        assertEq(IMplRewards(mplRewards).balanceOf(address(usdcDeposit)), 0);
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

    function testWithdrawWithoutExitingNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdrawWithoutExiting(address(this), targetUsdcBalance);
    }

    function testWithdrawFromRewardsContractgNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdrawFromRewardsContract();
    }

    function testWithdrawAllNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdrawAll(address(this));
    }

    function testExitPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.exit();
    }

    function testEmergencyActionNonPCVControllerFails() public {
        MaplePCVDeposit.Call[] memory calls = new MaplePCVDeposit.Call[](2);

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.emergencyAction(calls);
    }
}

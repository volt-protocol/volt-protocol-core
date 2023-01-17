//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {CoreV2} from "../../core/CoreV2.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {IDSSPSM} from "../../pcv/maker/IDSSPSM.sol";
import {Constants} from "../../Constants.sol";
import {getCoreV2} from "./../unit/utils/Fixtures.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {SystemEntry} from "../../entry/SystemEntry.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {MorphoCompoundPCVDeposit} from "../../pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {TestAddresses as addresses} from "../unit/utils/TestAddresses.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "../../core/GlobalReentrancyLock.sol";

contract IntegrationTestMorphoCompoundPCVDeposit is DSTest {
    using SafeCast for *;

    // Constant addresses
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address private constant CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address private constant CUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address private constant MORPHO =
        0x8888882f8f843896699869179fB6E4f7e3B58888;
    address private constant MORPHO_LENS =
        0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67;
    address private constant DAI_USDC_USDT_CURVE_POOL =
        0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    CoreV2 private core;
    SystemEntry public entry;
    GlobalReentrancyLock private lock;
    MorphoCompoundPCVDeposit private daiDeposit;
    MorphoCompoundPCVDeposit private usdcDeposit;

    PCVGuardian private pcvGuardian;

    IERC20 private dai = IERC20(DAI);
    IERC20 private usdc = IERC20(USDC);
    IERC20 private comp = IERC20(COMP);

    uint256 public daiBalance;
    uint256 public usdcBalance;

    uint256 targetDaiBalance = 100_000e18;
    uint256 targetUsdcBalance = 100_000e6;

    uint256 public constant epochLength = 100 days;

    function setUp() public {
        core = getCoreV2();
        lock = new GlobalReentrancyLock(address(core));
        daiDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            CDAI,
            DAI,
            MORPHO,
            MORPHO_LENS
        );

        usdcDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            CUSDC,
            USDC,
            MORPHO,
            MORPHO_LENS
        );

        entry = new SystemEntry(address(core));

        address[] memory toWhitelist = new address[](2);
        toWhitelist[0] = address(usdcDeposit);
        toWhitelist[1] = address(daiDeposit);

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this),
            toWhitelist
        );

        vm.label(address(daiDeposit), "Morpho DAI Compound PCV Deposit");
        vm.label(address(usdcDeposit), "Morpho USDC Compound PCV Deposit");
        vm.label(address(CDAI), "CDAI");
        vm.label(address(CUSDC), "CUSDC");
        vm.label(address(usdc), "USDC");
        vm.label(address(dai), "DAI");
        vm.label(0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67, "Morpho Lens");
        vm.label(0x8888882f8f843896699869179fB6E4f7e3B58888, "Morpho");

        vm.startPrank(DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(daiDeposit), targetDaiBalance);
        usdc.transfer(address(usdcDeposit), targetUsdcBalance);
        vm.stopPrank();

        vm.startPrank(addresses.governorAddress);

        core.setGlobalReentrancyLock(IGlobalReentrancyLock(address(lock)));

        core.grantPCVGuard(address(this));
        core.grantPCVController(address(pcvGuardian));

        core.grantLocker(address(entry));
        core.grantLocker(address(daiDeposit));
        core.grantLocker(address(usdcDeposit));
        core.grantLocker(address(pcvGuardian));

        vm.stopPrank();

        entry.deposit(address(daiDeposit));
        entry.deposit(address(usdcDeposit));

        vm.roll(block.number + 1); /// fast forward 1 block so that profit is positive
    }

    function testSetup() public {
        assertEq(address(daiDeposit.core()), address(core));
        assertEq(address(usdcDeposit.core()), address(core));
        assertEq(daiDeposit.morpho(), MORPHO);
        assertEq(usdcDeposit.morpho(), MORPHO);
        assertEq(daiDeposit.lens(), MORPHO_LENS);
        assertEq(usdcDeposit.lens(), MORPHO_LENS);

        assertEq(daiDeposit.balanceReportedIn(), address(dai));
        assertEq(usdcDeposit.balanceReportedIn(), address(usdc));

        assertEq(address(daiDeposit.cToken()), address(CDAI));
        assertEq(address(usdcDeposit.cToken()), address(CUSDC));

        assertEq(address(daiDeposit.token()), address(DAI));
        assertEq(address(usdcDeposit.token()), address(USDC));

        assertEq(daiDeposit.lastRecordedBalance(), targetDaiBalance);
        assertEq(usdcDeposit.lastRecordedBalance(), targetUsdcBalance);

        assertApproxEq(
            daiDeposit.balance().toInt256(),
            targetDaiBalance.toInt256(),
            0
        );
        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
    }

    function testWithdraw() public {
        pcvGuardian.withdrawToSafeAddress(
            address(usdcDeposit),
            usdcDeposit.balance()
        );
        pcvGuardian.withdrawToSafeAddress(
            address(daiDeposit),
            daiDeposit.balance()
        );

        assertApproxEq(
            dai.balanceOf(address(this)).toInt256(),
            targetDaiBalance.toInt256(),
            0
        );
        assertApproxEq(
            usdc.balanceOf(address(this)).toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
    }

    function testHarvest() public {
        /// fast forward block number amount
        vm.roll(block.number + epochLength / 12);

        uint256 startingCompBalance = comp.balanceOf(address(usdcDeposit)) +
            comp.balanceOf(address(daiDeposit));

        entry.harvest(address(usdcDeposit));
        entry.harvest(address(daiDeposit));

        uint256 endingCompBalance = comp.balanceOf(address(usdcDeposit)) +
            comp.balanceOf(address(daiDeposit));

        uint256 compDelta = endingCompBalance - startingCompBalance;

        assertTrue(compDelta != 0);
    }

    /// 2**80 / 1e18 = ~1.2m which is above target dai balance
    function testWithdrawDaiFuzz(uint80 amount) public {
        /// 1 fails in some underlying contract, and this isn't a scenario we are going to realistically have
        /// as 1e9 wei of dai would always cost more in gas than the dai is worth
        vm.assume(amount >= 1e9);
        vm.assume(amount <= targetDaiBalance);

        pcvGuardian.withdrawToSafeAddress(address(daiDeposit), amount);

        assertEq(dai.balanceOf(address(this)), amount);

        assertApproxEq(
            daiDeposit.balance().toInt256(),
            (targetDaiBalance - amount).toInt256(),
            0
        );
    }

    function testWithdrawUsdcFuzz(uint40 amount) public {
        vm.assume(amount != 0);
        vm.assume(amount <= targetUsdcBalance);

        pcvGuardian.withdrawToSafeAddress(address(usdcDeposit), amount);

        assertEq(usdc.balanceOf(address(this)), amount);

        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            (targetUsdcBalance - amount).toInt256(),
            0
        );
    }

    function testWithdrawAll() public {
        pcvGuardian.withdrawAllToSafeAddress(address(usdcDeposit));
        pcvGuardian.withdrawAllToSafeAddress(address(daiDeposit));

        assertApproxEq(
            dai.balanceOf(address(this)).toInt256(),
            targetDaiBalance.toInt256(),
            0
        );

        assertApproxEq(
            usdc.balanceOf(address(this)).toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
    }

    function testDepositNoFundsSucceeds() public {
        entry.deposit(address(usdcDeposit));
        entry.deposit(address(daiDeposit));
    }

    function testAccrueNoFundsSucceeds() public {
        entry.accrue(address(usdcDeposit));
        entry.accrue(address(daiDeposit));
    }

    function testDepositWhenPausedFails() public {
        vm.prank(addresses.governorAddress);
        usdcDeposit.pause();

        vm.expectRevert("Pausable: paused");
        entry.deposit(address(usdcDeposit));

        vm.prank(addresses.governorAddress);
        daiDeposit.pause();

        vm.expectRevert("Pausable: paused");
        entry.deposit(address(daiDeposit));
    }

    function testWithdrawNonPCVControllerFails() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        lock.lock(1);
        vm.stopPrank();

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdraw(address(this), targetUsdcBalance);

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        daiDeposit.withdraw(address(this), targetDaiBalance);
    }

    function testWithdrawAllNonPCVControllerFails() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        lock.lock(1);
        vm.stopPrank();

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdrawAll(address(this));

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        daiDeposit.withdrawAll(address(this));
    }
}

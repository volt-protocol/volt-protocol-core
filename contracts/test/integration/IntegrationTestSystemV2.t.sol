// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Vm} from "../unit/utils/Vm.sol";
import {Test} from "../../../forge-std/src/Test.sol";

// import everything from SystemV2
import "../../deployment/SystemV2.sol";
import {VoltRoles} from "../../core/VoltRoles.sol";

contract IntegrationTestSystemV2 is Test {
    using SafeCast for *;
    SystemV2 systemV2;
    address public constant user = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    CoreV2 core;
    IERC20 dai;
    IERC20 usdc;
    VoltV2 volt;
    NonCustodialPSM daincpsm;
    PegStabilityModule daipsm;
    NonCustodialPSM usdcncpsm;
    PegStabilityModule usdcpsm;
    GlobalRateLimitedMinter grlm;
    GlobalSystemExitRateLimiter gserl;
    ERC20Allocator allocator;
    PCVOracle pcvOracle;
    TimelockController timelockController;
    PCVGuardian pcvGuardian;
    MorphoCompoundPCVDeposit morphoDaiPCVDeposit;
    MorphoCompoundPCVDeposit morphoUsdcPCVDeposit;
    PCVRouter pcvRouter;
    SystemEntry systemEntry;

    function setUp() public {
        systemV2 = new SystemV2();
        systemV2.deploy();
        systemV2.setUp(address(systemV2));
        core = systemV2.core();
        dai = systemV2.dai();
        usdc = systemV2.usdc();
        volt = systemV2.volt();
        grlm = systemV2.grlm();
        gserl = systemV2.gserl();
        daipsm = systemV2.daipsm();
        daincpsm = systemV2.daiNonCustodialPsm();
        usdcncpsm = systemV2.usdcNonCustodialPsm();
        usdcpsm = systemV2.usdcpsm();
        allocator = systemV2.allocator();
        pcvOracle = systemV2.pcvOracle();
        timelockController = systemV2.timelockController();
        pcvGuardian = systemV2.pcvGuardian();
        morphoDaiPCVDeposit = systemV2.morphoDaiPCVDeposit();
        morphoUsdcPCVDeposit = systemV2.morphoUsdcPCVDeposit();
        pcvRouter = systemV2.pcvRouter();
        systemEntry = systemV2.systemEntry();

        uint256 BUFFER_CAP_MINTING = systemV2.BUFFER_CAP_MINTING();
        uint256 amount = BUFFER_CAP_MINTING / 2;

        deal(address(dai), user, amount);
    }

    /*
    Validate that the smart contracts are correctly linked to each other.
    */
    function testLinks() public {
        // core references
        assertEq(address(core.volt()), address(systemV2.volt()));
        assertEq(address(core.vcon()), address(0));
        assertEq(
            address(core.globalRateLimitedMinter()),
            address(systemV2.grlm())
        );
        assertEq(
            address(core.globalSystemExitRateLimiter()),
            address(systemV2.gserl())
        );
        assertEq(address(core.pcvOracle()), address(systemV2.pcvOracle()));

        // psm allocator
        assertEq(
            allocator.pcvDepositToPSM(address(systemV2.morphoUsdcPCVDeposit())),
            address(systemV2.usdcpsm())
        );
        assertEq(
            allocator.pcvDepositToPSM(address(systemV2.morphoDaiPCVDeposit())),
            address(systemV2.daipsm())
        );
        (address psmToken1, , ) = allocator.allPSMs(address(systemV2.daipsm()));
        (address psmToken2, , ) = allocator.allPSMs(
            address(systemV2.usdcpsm())
        );
        assertEq(psmToken1, address(systemV2.dai()));
        assertEq(psmToken2, address(systemV2.usdc()));

        // pcv oracle
        assertEq(pcvOracle.getAllVenues().length, 2);
        assertEq(
            pcvOracle.getAllVenues()[0],
            address(systemV2.morphoDaiPCVDeposit())
        );
        assertEq(
            pcvOracle.getAllVenues()[1],
            address(systemV2.morphoUsdcPCVDeposit())
        );

        // pcv router
        assertTrue(pcvRouter.isPCVSwapper(address(systemV2.pcvSwapperMaker())));
    }

    /*
    Test that the roles are properly configured in the new system and that no
    additional roles are granted to unexpected addresses.
    */
    function testRoles() public {
        // GOVERNOR
        assertEq(core.getRoleMemberCount(VoltRoles.GOVERNOR), 3);
        assertEq(core.getRoleMember(VoltRoles.GOVERNOR, 0), address(core));
        assertEq(
            core.getRoleMember(VoltRoles.GOVERNOR, 1),
            MainnetAddresses.GOVERNOR
        );
        assertEq(
            core.getRoleMember(VoltRoles.GOVERNOR, 2),
            address(systemV2.timelockController())
        );

        // PCV_CONTROLLER
        assertEq(core.getRoleMemberCount(VoltRoles.PCV_CONTROLLER), 6);
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 0),
            address(systemV2.allocator())
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 1),
            address(systemV2.pcvGuardian())
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 2),
            address(systemV2.pcvRouter())
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 3),
            MainnetAddresses.GOVERNOR
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 4),
            address(systemV2.daiNonCustodialPsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 5),
            address(systemV2.usdcNonCustodialPsm())
        );

        // PCV_MOVER
        assertEq(core.getRoleMemberCount(VoltRoles.PCV_MOVER), 1);
        assertEq(
            core.getRoleMember(VoltRoles.PCV_MOVER, 0),
            MainnetAddresses.GOVERNOR
        );

        // LIQUID_PCV_DEPOSIT_ROLE
        assertEq(core.getRoleMemberCount(VoltRoles.LIQUID_PCV_DEPOSIT), 4);
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT, 0),
            address(systemV2.daipsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT, 1),
            address(systemV2.usdcpsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT, 2),
            address(systemV2.morphoDaiPCVDeposit())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT, 3),
            address(systemV2.morphoUsdcPCVDeposit())
        );

        // ILLIQUID_PCV_DEPOSIT_ROLE
        assertEq(core.getRoleMemberCount(VoltRoles.ILLIQUID_PCV_DEPOSIT), 0);

        // PCV_GUARD
        assertEq(core.getRoleMemberCount(VoltRoles.PCV_GUARD), 3);
        assertEq(
            core.getRoleMember(VoltRoles.PCV_GUARD, 0),
            MainnetAddresses.EOA_1
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_GUARD, 1),
            MainnetAddresses.EOA_2
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_GUARD, 2),
            MainnetAddresses.EOA_4
        );

        // GUARDIAN
        assertEq(core.getRoleMemberCount(VoltRoles.GUARDIAN), 1);
        assertEq(
            core.getRoleMember(VoltRoles.GUARDIAN, 0),
            address(systemV2.pcvGuardian())
        );

        // RATE_LIMIT_SYSTEM_ENTRY_DEPLETE_ROLE
        assertEq(
            core.getRoleMemberCount(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_DEPLETE),
            2
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_DEPLETE, 0),
            address(systemV2.daipsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_DEPLETE, 1),
            address(systemV2.usdcpsm())
        );

        // RATE_LIMIT_SYSTEM_ENTRY_REPLENISH_ROLE
        assertEq(
            core.getRoleMemberCount(
                VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_REPLENISH
            ),
            4
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_REPLENISH, 0),
            address(systemV2.daipsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_REPLENISH, 1),
            address(systemV2.usdcpsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_REPLENISH, 2),
            address(systemV2.daiNonCustodialPsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_REPLENISH, 3),
            address(systemV2.usdcNonCustodialPsm())
        );

        // LOCKER_ROLE
        assertEq(core.getRoleMemberCount(VoltRoles.LOCKER), 13);
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 0),
            address(systemV2.systemEntry())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 1),
            address(systemV2.allocator())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 2),
            address(systemV2.pcvOracle())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 3),
            address(systemV2.daipsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 4),
            address(systemV2.usdcpsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 5),
            address(systemV2.morphoDaiPCVDeposit())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 6),
            address(systemV2.morphoUsdcPCVDeposit())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 7),
            address(systemV2.grlm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 8),
            address(systemV2.gserl())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 9),
            address(systemV2.pcvRouter())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 10),
            address(systemV2.pcvGuardian())
        );
        assertEq(core.getRoleMember(VoltRoles.LOCKER, 11), address(daincpsm));
        assertEq(core.getRoleMember(VoltRoles.LOCKER, 12), address(usdcncpsm));

        // MINTER
        assertEq(core.getRoleMemberCount(VoltRoles.MINTER), 1);
        assertEq(
            core.getRoleMember(VoltRoles.MINTER, 0),
            address(systemV2.grlm())
        );

        /// SYSTEM EXIT RATE LIMIT DEPLETER
        assertEq(
            core.getRoleMemberCount(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_DEPLETE),
            2
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_DEPLETE, 0),
            address(systemV2.daiNonCustodialPsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_DEPLETE, 1),
            address(systemV2.usdcNonCustodialPsm())
        );

        /// SYSTEM EXIT RATE LIMIT REPLENISH
        assertEq(
            core.getRoleMemberCount(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_DEPLETE),
            2
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_REPLENISH, 0),
            address(systemV2.allocator())
        );
    }

    function testTimelockRoles() public {
        bytes32 executor = timelockController.EXECUTOR_ROLE();
        bytes32 canceller = timelockController.CANCELLER_ROLE();
        bytes32 proposer = timelockController.PROPOSER_ROLE();

        assertTrue(timelockController.hasRole(executor, address(0))); /// role open
        assertTrue(
            timelockController.hasRole(canceller, MainnetAddresses.GOVERNOR)
        );
        assertTrue(
            timelockController.hasRole(proposer, MainnetAddresses.GOVERNOR)
        );
        assertTrue(!timelockController.hasRole(canceller, address(0))); /// role closed
        assertTrue(!timelockController.hasRole(proposer, address(0))); /// role closed
    }

    function testMultisigProposesTimelock() public {
        uint256 ethSendAmount = 100 ether;
        vm.deal(address(timelockController), ethSendAmount);

        assertEq(address(timelockController).balance, ethSendAmount); /// starts with 0 balance

        bytes memory data = "";
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);
        address recipient = address(100);

        vm.prank(MainnetAddresses.GOVERNOR);
        timelockController.schedule(
            recipient,
            ethSendAmount,
            data,
            predecessor,
            salt,
            86400
        );
        bytes32 id = timelockController.hashOperation(
            recipient,
            ethSendAmount,
            data,
            predecessor,
            salt
        );

        uint256 startingEthBalance = recipient.balance;

        assertTrue(!timelockController.isOperationDone(id)); /// operation is not done
        assertTrue(!timelockController.isOperationReady(id)); /// operation is not ready

        vm.warp(block.timestamp + timelockController.getMinDelay());
        assertTrue(timelockController.isOperationReady(id)); /// operation is ready

        timelockController.execute(
            recipient,
            ethSendAmount,
            data,
            predecessor,
            salt
        );

        assertTrue(timelockController.isOperationDone(id)); /// operation is done

        assertEq(address(timelockController).balance, 0);
        assertEq(recipient.balance, ethSendAmount + startingEthBalance); /// assert receiver received their eth
    }

    function testOraclePriceAndReference() public {
        address oracleAddress = address(systemV2.vso());

        assertEq(address(systemV2.daipsm().oracle()), oracleAddress);
        assertEq(address(systemV2.usdcpsm().oracle()), oracleAddress);

        assertEq(
            systemV2.vso().getCurrentOraclePrice(),
            systemV2.VOLT_START_PRICE()
        );
    }

    function testCoreReferences() public {
        address coreAddress = address(core);

        assertEq(address(systemV2.daipsm().core()), coreAddress);
        assertEq(address(systemV2.usdcpsm().core()), coreAddress);
        assertEq(address(systemV2.volt().core()), coreAddress);
        assertEq(address(systemV2.grlm().core()), coreAddress);
        assertEq(address(systemV2.gserl().core()), coreAddress);
        assertEq(address(systemV2.vso().core()), coreAddress);
        assertEq(address(systemV2.morphoDaiPCVDeposit().core()), coreAddress);
        assertEq(address(systemV2.morphoUsdcPCVDeposit().core()), coreAddress);
        assertEq(address(systemV2.usdcNonCustodialPsm().core()), coreAddress);
        assertEq(address(systemV2.daiNonCustodialPsm().core()), coreAddress);
        assertEq(address(systemV2.allocator().core()), coreAddress);
        assertEq(address(systemV2.systemEntry().core()), coreAddress);
        assertEq(address(systemV2.pcvSwapperMaker().core()), coreAddress);
        assertEq(address(systemV2.pcvGuardian().core()), coreAddress);
        assertEq(address(systemV2.pcvRouter().core()), coreAddress);
        assertEq(address(systemV2.pcvOracle().core()), coreAddress);
        assertEq(address(systemV2.daiConstantOracle().core()), coreAddress);
        assertEq(address(systemV2.usdcConstantOracle().core()), coreAddress);
    }

    /*
    Flow of the first user that mints VOLT in the new system.
    Performs checks on the global rate limits, and accounting
    in the new system's PCV Oracle.
    */
    function testFirstUserMint() public {
        // setup variables
        uint256 BUFFER_CAP_MINTING = systemV2.BUFFER_CAP_MINTING();
        uint256 amount = BUFFER_CAP_MINTING / 2;
        uint256 daiTargetBalance = systemV2.DAI_TARGET_BALANCE();
        uint256 expectDaiBalance = amount - daiTargetBalance;

        // at system deloy, buffer is full
        assertEq(grlm.buffer(), BUFFER_CAP_MINTING);

        {
            // at system deploy, pcv is 0
            (
                uint256 liquidPcv1,
                uint256 illiquidPcv1,
                uint256 totalPcv1
            ) = pcvOracle.getTotalPcv();
            assertEq(liquidPcv1, 0);
            assertEq(illiquidPcv1, 0);
            assertEq(totalPcv1, 0);
        }

        // user performs the first mint
        vm.startPrank(user);
        dai.approve(address(daipsm), amount);
        daipsm.mint(user, amount, 0);
        vm.stopPrank();

        // buffer has been used
        uint256 voltReceived1 = volt.balanceOf(user);
        assertEq(grlm.buffer(), BUFFER_CAP_MINTING - voltReceived1);

        // user received VOLT
        assertTrue(voltReceived1 > (90 * amount) / 100);
        // psm received DAI
        assertEq(daipsm.balance(), amount);

        allocator.skim(address(morphoDaiPCVDeposit));
        {
            // after first mint, pcv is = amount
            (
                uint256 liquidPcv2,
                uint256 illiquidPcv2,
                uint256 totalPcv2
            ) = pcvOracle.getTotalPcv();
            assertApproxEq(
                liquidPcv2.toInt256(),
                expectDaiBalance.toInt256(),
                0
            );
            assertApproxEq(
                totalPcv2.toInt256(),
                expectDaiBalance.toInt256(),
                0
            );
            assertEq(illiquidPcv2, 0);
        }

        // user performs the second mint
        vm.startPrank(user);
        usdc.approve(address(usdcpsm), amount / 1e12);
        usdcpsm.mint(user, amount / 1e12, 0);
        vm.stopPrank();
        uint256 voltReceived2 = volt.balanceOf(user) - voltReceived1;

        // buffer has been used
        assertEq(
            grlm.buffer(),
            systemV2.BUFFER_CAP_MINTING() - voltReceived1 - voltReceived2
        );

        // user received VOLT
        assertTrue(voltReceived2 > (90 * amount) / 100);
        // psm received USDC
        assertEq(usdcpsm.balance(), amount / 1e12);

        allocator.skim(address(morphoUsdcPCVDeposit));
        {
            // after second mint, pcv is = 2 * amount
            (
                uint256 liquidPcv3,
                uint256 illiquidPcv3,
                uint256 totalPcv3
            ) = pcvOracle.getTotalPcv();
            assertEq(illiquidPcv3, 0);
            assertApproxEq(
                totalPcv3.toInt256(),
                2 * expectDaiBalance.toInt256(),
                0
            );
            assertApproxEq(
                liquidPcv3.toInt256(),
                2 * expectDaiBalance.toInt256(),
                0
            );
        }
        vm.snapshot();

        vm.prank(address(core));
        grlm.setRateLimitPerSecond(5.787e18);

        // buffer replenishes over time
        vm.warp(block.timestamp + 3 days);

        // above limit rate reverts
        vm.startPrank(user);
        dai.approve(address(daipsm), BUFFER_CAP_MINTING * 2);
        vm.expectRevert("RateLimited: rate limit hit");
        daipsm.mint(user, BUFFER_CAP_MINTING * 2, 0);
        vm.stopPrank();
    }

    function testRedeemsDaiPsm(uint88 voltAmount) public {
        testFirstUserMint();

        uint256 snapshotId = 0; /// roll back to before buffer replenished
        vm.revertTo(snapshotId);
        vm.assume(voltAmount <= volt.balanceOf(user));

        {
            uint256 daiAmountOut = daipsm.getRedeemAmountOut(voltAmount);
            deal(address(dai), address(daipsm), daiAmountOut);

            vm.startPrank(user);

            uint256 startingBuffer = grlm.buffer();
            uint256 startingDaiBalance = dai.balanceOf(user);

            volt.approve(address(daipsm), voltAmount);
            daipsm.redeem(user, voltAmount, daiAmountOut);

            uint256 endingBuffer = grlm.buffer();
            uint256 endingDaiBalance = dai.balanceOf(user);

            assertEq(endingDaiBalance - startingDaiBalance, daiAmountOut);
            assertEq(endingBuffer - startingBuffer, voltAmount);

            vm.stopPrank();
        }
    }

    function testRedeemsDaiNcPsm(uint80 voltRedeemAmount) public {
        vm.assume(voltRedeemAmount >= 1e18);
        vm.assume(voltRedeemAmount <= 475_000e18);
        testFirstUserMint();

        uint256 snapshotId = 0; /// roll back to before buffer replenished
        vm.revertTo(snapshotId);

        {
            uint256 daiAmountOut = daincpsm.getRedeemAmountOut(
                voltRedeemAmount
            );
            deal(address(dai), address(morphoDaiPCVDeposit), daiAmountOut * 2);
            systemEntry.deposit(address(morphoDaiPCVDeposit));

            vm.startPrank(user);

            uint256 startingBuffer = grlm.buffer();
            uint256 startingExitBuffer = gserl.buffer();
            uint256 startingDaiBalance = dai.balanceOf(user);

            volt.approve(address(daincpsm), voltRedeemAmount);
            daincpsm.redeem(user, voltRedeemAmount, daiAmountOut);

            uint256 endingBuffer = grlm.buffer();
            uint256 endingExitBuffer = gserl.buffer();
            uint256 endingDaiBalance = dai.balanceOf(user);

            assertEq(endingBuffer - startingBuffer, voltRedeemAmount); /// grlm buffer replenished
            assertEq(endingDaiBalance - startingDaiBalance, daiAmountOut);
            assertEq(startingExitBuffer - endingExitBuffer, daiAmountOut); /// exit buffer depleted

            vm.stopPrank();
        }
    }

    function testRedeemsUsdcNcPsm(uint80 voltRedeemAmount) public {
        vm.assume(voltRedeemAmount >= 1e18);
        vm.assume(voltRedeemAmount <= 475_000e18);
        testFirstUserMint();

        uint256 snapshotId = 0; /// roll back to before buffer replenished
        vm.revertTo(snapshotId);

        {
            uint256 usdcAmountOut = usdcncpsm.getRedeemAmountOut(
                voltRedeemAmount
            );
            deal(
                address(usdc),
                address(morphoUsdcPCVDeposit),
                usdcAmountOut * 2
            );
            systemEntry.deposit(address(morphoUsdcPCVDeposit));

            vm.startPrank(user);

            uint256 startingBuffer = grlm.buffer();
            uint256 startingExitBuffer = gserl.buffer();
            uint256 startingUsdcBalance = usdc.balanceOf(user);

            volt.approve(address(usdcncpsm), voltRedeemAmount);
            usdcncpsm.redeem(user, voltRedeemAmount, usdcAmountOut);

            uint256 endingBuffer = grlm.buffer();
            uint256 endingExitBuffer = gserl.buffer();
            uint256 endingUsdcBalance = usdc.balanceOf(user);

            assertEq(endingBuffer - startingBuffer, voltRedeemAmount); /// buffer replenished
            assertEq(endingUsdcBalance - startingUsdcBalance, usdcAmountOut);
            assertEq(
                startingExitBuffer - endingExitBuffer,
                usdcAmountOut * 1e12
            ); /// ensure buffer adjusted up 12 decimals, buffer depleted

            vm.stopPrank();
        }
    }

    function testRedeemsUsdcPsm(uint80 voltRedeemAmount) public {
        vm.assume(voltRedeemAmount >= 1e18);
        vm.assume(voltRedeemAmount <= 475_000e18);
        testFirstUserMint();

        uint256 snapshotId = 0; /// roll back to before buffer replenished
        vm.revertTo(snapshotId);

        {
            uint256 usdcAmountOut = usdcpsm.getRedeemAmountOut(
                voltRedeemAmount
            );
            deal(address(usdc), address(usdcpsm), usdcAmountOut);

            vm.startPrank(user);

            uint256 startingBuffer = grlm.buffer();
            uint256 startingUsdcBalance = usdc.balanceOf(user);

            volt.approve(address(usdcpsm), voltRedeemAmount);
            usdcpsm.redeem(user, voltRedeemAmount, usdcAmountOut);

            uint256 endingBuffer = grlm.buffer();
            uint256 endingUsdcBalance = usdc.balanceOf(user);

            assertEq(endingBuffer - startingBuffer, voltRedeemAmount);
            assertEq(endingUsdcBalance - startingUsdcBalance, usdcAmountOut);

            vm.stopPrank();
        }
    }

    /*
    Migrate PCV from current system to V2 system, and perform sanity checks on amounts.
    */
    function testMigratePcv() public {
        uint256 migratedPcv = _migratePcv();

        // get PCV stats
        (uint256 liquidPcv, uint256 illiquidPcv, uint256 totalPcv) = systemV2
            .pcvOracle()
            .getTotalPcv();

        // sanity check
        assertEq(liquidPcv, totalPcv);
        assertEq(illiquidPcv, 0);
        assertGt(totalPcv, 1_500_000e18);
        assertGt(migratedPcv, 1_500_000e18);
    }

    /*
    After migrating to V2 system, check that we can use PCVGuardian.
    */
    function testPcvGuardian() public {
        _migratePcv();
        uint256 amount = 100_000e18;

        uint256 depositDaiBalanceBefore = morphoDaiPCVDeposit.balance();
        uint256 safeAddressDaiBalanceBefore = dai.balanceOf(
            address(timelockController)
        );

        vm.prank(MainnetAddresses.GOVERNOR);
        pcvGuardian.withdrawToSafeAddress(address(morphoDaiPCVDeposit), amount);

        uint256 depositDaiBalanceAfter = morphoDaiPCVDeposit.balance();
        uint256 safeAddressDaiBalanceAfter = dai.balanceOf(
            address(timelockController)
        );

        // tolerate 0.5% err because morpho withdrawals are not exact
        assertGt(
            safeAddressDaiBalanceAfter - safeAddressDaiBalanceBefore,
            (995 * amount) / 1000
        );
        assertGt(
            depositDaiBalanceBefore - depositDaiBalanceAfter,
            (995 * amount) / 1000
        );
    }

    /*
    After migrating to V2 system, check that we can use PCVRouter + MakerPCVSwapper.
    Swap DAI to USDC, then USDC to DAI.
    */
    function testPcvRouterWithSwap() public {
        _migratePcv();
        uint256 amount = 100_000e18;

        uint256 depositDaiBalanceBefore = morphoDaiPCVDeposit.balance();
        uint256 depositUsdcBalanceBefore = morphoUsdcPCVDeposit.balance();

        // Swap DAI to USDC
        vm.startPrank(MainnetAddresses.GOVERNOR); // has PCV_MOVER role
        pcvRouter.movePCV(
            address(morphoDaiPCVDeposit), // source
            address(morphoUsdcPCVDeposit), // destination
            address(systemV2.pcvSwapperMaker()), // swapper
            amount, // amount
            address(systemV2.dai()), // sourceAsset
            address(systemV2.usdc()), // destinationAsset
            true, // sourceIsLiquid
            true // destinationIsLiquid
        );
        vm.stopPrank();

        uint256 depositDaiBalanceAfter = morphoDaiPCVDeposit.balance();
        uint256 depositUsdcBalanceAfter = morphoUsdcPCVDeposit.balance();

        // tolerate 0.5% err because morpho withdrawals are not exact
        assertGt(
            depositDaiBalanceBefore - depositDaiBalanceAfter,
            (995 * amount) / 1000
        );
        assertGt(
            depositUsdcBalanceAfter - depositUsdcBalanceBefore,
            ((995 * amount) / 1e12) / 1000
        );

        // Swap USDC to DAI (half of previous amount)
        vm.startPrank(MainnetAddresses.GOVERNOR); // has PCV_MOVER role
        pcvRouter.movePCV(
            address(morphoUsdcPCVDeposit), // source
            address(morphoDaiPCVDeposit), // destination
            address(systemV2.pcvSwapperMaker()), // swapper
            amount / 2e12, // amount
            address(systemV2.usdc()), // sourceAsset
            address(systemV2.dai()), // destinationAsset
            true, // sourceIsLiquid
            true // destinationIsLiquid
        );
        vm.stopPrank();

        uint256 depositDaiBalanceFinal = morphoDaiPCVDeposit.balance();
        uint256 depositUsdcBalanceFinal = morphoUsdcPCVDeposit.balance();

        // tolerate 0.5% err because morpho withdrawals are not exact
        assertGt(
            depositDaiBalanceFinal - depositDaiBalanceAfter,
            (995 * amount) / 2000
        );
        assertGt(
            depositUsdcBalanceAfter - depositUsdcBalanceFinal,
            ((995 * amount) / 1e12) / 2000
        );
    }

    /*
    After migrating to V2 system, check that we can unset the PCVOracle in Core
    and that it doesn't break PCV movements (only disables accounting).
    */
    function testUnsetPcvOracle() public {
        _migratePcv();

        vm.prank(MainnetAddresses.GOVERNOR);
        core.setPCVOracle(IPCVOracle(address(0)));

        vm.prank(MainnetAddresses.GOVERNOR);
        pcvGuardian.withdrawToSafeAddress(address(morphoDaiPCVDeposit), 100e18);

        // No revert & PCV moved
        assertEq(dai.balanceOf(pcvGuardian.safeAddress()), 100e18);

        // User redeems
        vm.prank(address(systemV2.grlm()));
        volt.mint(address(this), 100e18);
        volt.approve(address(daipsm), 100e18);
        daipsm.redeem(address(this), 100e18, 104e18);
        assertGt(dai.balanceOf(address(this)), 104e18);
    }

    /*
    Internal helper function, migrate the PCV from current system to V2 system
    */
    function _migratePcv() internal returns (uint256) {
        MorphoCompoundPCVDeposit oldMorphoDaiPCVDeposit = MorphoCompoundPCVDeposit(
                MainnetAddresses.MORPHO_COMPOUND_DAI_PCV_DEPOSIT
            );
        /*MorphoCompoundPCVDeposit oldMorphoUsdcPCVDeposit = MorphoCompoundPCVDeposit(
            MainnetAddresses.MORPHO_COMPOUND_USDC_PCV_DEPOSIT
        );*/
        PCVGuardian oldPCVGuardian = PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

        uint256 daiBalanceBefore = dai.balanceOf(MainnetAddresses.GOVERNOR);
        uint256 usdcBalanceBefore = usdc.balanceOf(MainnetAddresses.GOVERNOR);

        // Move all DAI and USDC to Safe Address
        vm.startPrank(MainnetAddresses.GOVERNOR);
        oldPCVGuardian.withdrawAllToSafeAddress(
            address(oldMorphoDaiPCVDeposit)
        );
        //oldPCVGuardian.withdrawAllToSafeAddress(address(oldMorphoUsdcPCVDeposit)); // reverts because 0
        oldPCVGuardian.withdrawAllERC20ToSafeAddress(
            MainnetAddresses.VOLT_DAI_PSM,
            MainnetAddresses.DAI
        );
        oldPCVGuardian.withdrawAllERC20ToSafeAddress(
            MainnetAddresses.VOLT_DAI_PSM,
            MainnetAddresses.VOLT
        );
        oldPCVGuardian.withdrawAllERC20ToSafeAddress(
            MainnetAddresses.VOLT_USDC_PSM,
            MainnetAddresses.USDC
        );
        oldPCVGuardian.withdrawAllERC20ToSafeAddress(
            MainnetAddresses.VOLT_USDC_PSM,
            MainnetAddresses.VOLT
        );
        vm.stopPrank();

        uint256 daiBalanceAfter = dai.balanceOf(MainnetAddresses.GOVERNOR);
        uint256 usdcBalanceAfter = usdc.balanceOf(MainnetAddresses.GOVERNOR);
        uint256 protocolDai = daiBalanceAfter - daiBalanceBefore;
        uint256 protocolUsdc = usdcBalanceAfter - usdcBalanceBefore;

        // Move DAI to expected location
        vm.startPrank(MainnetAddresses.GOVERNOR);
        dai.transfer(address(systemV2.daipsm()), 100_000e18);
        dai.transfer(
            address(systemV2.morphoDaiPCVDeposit()),
            protocolDai - 100_000e18
        );
        usdc.transfer(address(systemV2.usdcpsm()), protocolUsdc);
        systemEntry.deposit(address(systemV2.morphoDaiPCVDeposit()));
        vm.stopPrank();

        return protocolDai + protocolUsdc * 1e12;
    }
}

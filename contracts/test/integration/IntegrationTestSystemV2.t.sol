// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "../unit/utils/Vm.sol";
import {Test} from "../../../forge-std/src/Test.sol";

// import everything from SystemV2
import "../../deployment/SystemV2.sol";
import {VoltRoles} from "../../core/VoltRoles.sol";

contract IntegrationTestSystemV2 is Test {
    SystemV2 systemV2;

    function setUp() public {
        systemV2 = new SystemV2();
        systemV2.deploy();
        systemV2.setUp(address(this));
    }

    /*
    Validate that the smart contracts are correctly linked to each other.
    */
    function testLinks() public {
        // core references
        CoreV2 core = systemV2.core();
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
        ERC20Allocator allocator = systemV2.allocator();
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
        PCVOracle pcvOracle = systemV2.pcvOracle();
        assertEq(pcvOracle.getAllVenues().length, 4);
        assertEq(
            pcvOracle.getAllVenues()[0],
            address(systemV2.morphoDaiPCVDeposit())
        );
        assertEq(
            pcvOracle.getAllVenues()[1],
            address(systemV2.morphoUsdcPCVDeposit())
        );
        assertEq(pcvOracle.getAllVenues()[2], address(systemV2.daipsm()));
        assertEq(pcvOracle.getAllVenues()[3], address(systemV2.usdcpsm()));

        // pcv router
        PCVRouter pcvRouter = systemV2.pcvRouter();
        assertTrue(pcvRouter.isPCVSwapper(address(systemV2.pcvSwapperMaker())));
    }

    /*
    Test that the roles are properly configured in the new system and that no
    additional roles are granted to unexpected addresses.
    */
    function testRoles() public {
        CoreV2 core = systemV2.core();

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
        assertEq(core.getRoleMemberCount(VoltRoles.LIQUID_PCV_DEPOSIT_ROLE), 4);
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT_ROLE, 0),
            address(systemV2.daipsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT_ROLE, 1),
            address(systemV2.usdcpsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT_ROLE, 2),
            address(systemV2.morphoDaiPCVDeposit())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT_ROLE, 3),
            address(systemV2.morphoUsdcPCVDeposit())
        );

        // ILLIQUID_PCV_DEPOSIT_ROLE
        assertEq(
            core.getRoleMemberCount(VoltRoles.ILLIQUID_PCV_DEPOSIT_ROLE),
            0
        );

        // PCV_GUARD
        assertEq(core.getRoleMemberCount(VoltRoles.PCV_GUARD), 4);
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
            MainnetAddresses.EOA_3
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_GUARD, 3),
            MainnetAddresses.EOA_4
        );

        // GUARDIAN
        assertEq(core.getRoleMemberCount(VoltRoles.GUARDIAN), 1);
        assertEq(
            core.getRoleMember(VoltRoles.GUARDIAN, 0),
            address(systemV2.pcvGuardian())
        );

        // VOLT_RATE_LIMITED_MINTER_ROLE
        assertEq(
            core.getRoleMemberCount(VoltRoles.VOLT_RATE_LIMITED_MINTER_ROLE),
            2
        );
        assertEq(
            core.getRoleMember(VoltRoles.VOLT_RATE_LIMITED_MINTER_ROLE, 0),
            address(systemV2.daipsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.VOLT_RATE_LIMITED_MINTER_ROLE, 1),
            address(systemV2.usdcpsm())
        );

        // VOLT_RATE_LIMITED_REDEEMER_ROLE
        assertEq(
            core.getRoleMemberCount(VoltRoles.VOLT_RATE_LIMITED_REDEEMER_ROLE),
            4
        );
        assertEq(
            core.getRoleMember(VoltRoles.VOLT_RATE_LIMITED_REDEEMER_ROLE, 0),
            address(systemV2.daipsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.VOLT_RATE_LIMITED_REDEEMER_ROLE, 1),
            address(systemV2.usdcpsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.VOLT_RATE_LIMITED_REDEEMER_ROLE, 2),
            address(systemV2.daiNonCustodialPsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.VOLT_RATE_LIMITED_REDEEMER_ROLE, 3),
            address(systemV2.usdcNonCustodialPsm())
        );

        // LOCKER_ROLE
        assertEq(core.getRoleMemberCount(VoltRoles.LOCKER_ROLE), 11);
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER_ROLE, 0),
            address(systemV2.systemEntry())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER_ROLE, 1),
            address(systemV2.allocator())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER_ROLE, 2),
            address(systemV2.pcvOracle())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER_ROLE, 3),
            address(systemV2.daipsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER_ROLE, 4),
            address(systemV2.usdcpsm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER_ROLE, 5),
            address(systemV2.morphoDaiPCVDeposit())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER_ROLE, 6),
            address(systemV2.morphoUsdcPCVDeposit())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER_ROLE, 7),
            address(systemV2.grlm())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER_ROLE, 8),
            address(systemV2.gserl())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER_ROLE, 9),
            address(systemV2.pcvRouter())
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER_ROLE, 10),
            address(systemV2.pcvGuardian())
        );

        // MINTER
        assertEq(core.getRoleMemberCount(VoltRoles.MINTER), 1);
        assertEq(
            core.getRoleMember(VoltRoles.MINTER, 0),
            address(systemV2.grlm())
        );

        /// SYSTEM EXIT RATE LIMIT DEPLETER
        assertEq(
            core.getRoleMemberCount(
                VoltRoles.VOLT_SYSTEM_EXIT_RATE_LIMIT_DEPLETER_ROLE
            ),
            2
        );
        assertEq(
            core.getRoleMember(
                VoltRoles.VOLT_SYSTEM_EXIT_RATE_LIMIT_DEPLETER_ROLE,
                0
            ),
            address(systemV2.daiNonCustodialPsm())
        );
        assertEq(
            core.getRoleMember(
                VoltRoles.VOLT_SYSTEM_EXIT_RATE_LIMIT_DEPLETER_ROLE,
                1
            ),
            address(systemV2.usdcNonCustodialPsm())
        );

        /// SYSTEM EXIT RATE LIMIT REPLENISH
        assertEq(
            core.getRoleMemberCount(
                VoltRoles.VOLT_SYSTEM_EXIT_RATE_LIMIT_DEPLETER_ROLE
            ),
            2
        );
        assertEq(
            core.getRoleMember(
                VoltRoles.VOLT_SYSTEM_EXIT_RATE_LIMIT_REPLENISH_ROLE,
                0
            ),
            address(systemV2.allocator())
        );
    }

    /*
    Flow of the first user that mints VOLT in the new system.
    Performs checks on the global rate limits, and accounting
    in the new system's PCV Oracle.
    */
    function testFirstUserMint() public {
        // setup variables
        address user = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
        uint256 BUFFER_CAP_MINTING = systemV2.BUFFER_CAP_MINTING();
        uint256 amount = BUFFER_CAP_MINTING / 2;
        IERC20 dai = systemV2.dai();
        IERC20 usdc = systemV2.usdc();
        VoltV2 volt = systemV2.volt();
        GlobalRateLimitedMinter grlm = systemV2.grlm();
        PegStabilityModule daipsm = systemV2.daipsm();
        PegStabilityModule usdcpsm = systemV2.usdcpsm();
        PCVOracle pcvOracle = systemV2.pcvOracle();

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

        {
            // after first mint, pcv is = amount
            (
                uint256 liquidPcv2,
                uint256 illiquidPcv2,
                uint256 totalPcv2
            ) = pcvOracle.getTotalPcv();
            assertEq(liquidPcv2, amount);
            assertEq(illiquidPcv2, 0);
            assertEq(totalPcv2, amount);
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

        {
            // after second mint, pcv is = 2 * amount
            (
                uint256 liquidPcv3,
                uint256 illiquidPcv3,
                uint256 totalPcv3
            ) = pcvOracle.getTotalPcv();
            assertEq(liquidPcv3, 2 * amount);
            assertEq(illiquidPcv3, 0);
            assertEq(totalPcv3, 2 * amount);
        }

        // buffer replenishes over time
        vm.warp(block.timestamp + 3 days);
        assertEq(grlm.buffer(), BUFFER_CAP_MINTING);

        // above limit rate reverts
        vm.startPrank(user);
        dai.approve(address(daipsm), BUFFER_CAP_MINTING * 2);
        vm.expectRevert("RateLimited: rate limit hit");
        daipsm.mint(user, BUFFER_CAP_MINTING * 2, 0);
        vm.stopPrank();
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
        assertGt(totalPcv, 1_900_000e18);
        assertGt(migratedPcv, 1_900_000e18);
    }

    /*
    After migrating to V2 system, check that we can use PCVGuardian.
    */
    function testPcvGuardian() public {
        _migratePcv();
        uint256 amount = 100_000e18;
        PCVGuardian pcvGuardian = systemV2.pcvGuardian();
        IERC20 dai = systemV2.dai();
        MorphoCompoundPCVDeposit morphoDaiPCVDeposit = systemV2
            .morphoDaiPCVDeposit();
        TimelockController timelockController = systemV2.timelockController();

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
        PCVRouter pcvRouter = systemV2.pcvRouter();
        MorphoCompoundPCVDeposit morphoDaiPCVDeposit = systemV2
            .morphoDaiPCVDeposit();
        MorphoCompoundPCVDeposit morphoUsdcPCVDeposit = systemV2
            .morphoUsdcPCVDeposit();

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
        CoreV2 core = systemV2.core();
        IERC20 dai = systemV2.dai();
        VoltV2 volt = systemV2.volt();
        PegStabilityModule daipsm = systemV2.daipsm();
        PCVGuardian pcvGuardian = systemV2.pcvGuardian();
        MorphoCompoundPCVDeposit morphoDaiPCVDeposit = systemV2
            .morphoDaiPCVDeposit();

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
        daipsm.redeem(address(this), 100e18, 105e18);
        assertGt(dai.balanceOf(address(this)), 105e18);
    }

    /*
    Internal helper function, migrate the PCV from current system to V2 system
    */
    function _migratePcv() internal returns (uint256) {
        IERC20 dai = systemV2.dai();
        IERC20 usdc = systemV2.usdc();
        MorphoCompoundPCVDeposit oldMorphoDaiPCVDeposit = MorphoCompoundPCVDeposit(
                MainnetAddresses.MORPHO_COMPOUND_DAI_PCV_DEPOSIT
            );
        /*MorphoCompoundPCVDeposit oldMorphoUsdcPCVDeposit = MorphoCompoundPCVDeposit(
            MainnetAddresses.MORPHO_COMPOUND_USDC_PCV_DEPOSIT
        );*/
        PCVGuardian oldPCVGuardian = PCVGuardian(MainnetAddresses.PCV_GUARDIAN);
        SystemEntry systemEntry = systemV2.systemEntry();

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

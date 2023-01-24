pragma solidity 0.8.13;

import {console} from "@forge-std/console.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {MockPCVSwapper} from "@test/mock/MockPCVSwapper.sol";
import {SystemUnitTest} from "@test/unit/system/System.t.sol";
import {MockPCVDepositV3} from "@test/mock/MockPCVDepositV3.sol";
import {MarketGovernance} from "@voltprotocol/vcon/MarketGovernance.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";

contract UnitTestMarketGovernance is SystemUnitTest {
    MarketGovernance public mgov;
    MockPCVSwapper public pcvSwapper;
    address public venue = address(10); /// a in hex
    uint256 public profitToVconRatio = 5; /// for each 1 wei in profit, 5 wei of vcon is received
    uint256 public daiDepositAmount = 1_000_000e18;
    uint256 public usdcDepositAmount = 1_000_000e6;

    uint256 public vconDepositAmount = 1_000_000e18;

    function setUp() public override {
        super.setUp();

        /// can only swap from dai to usdc
        pcvSwapper = new MockPCVSwapper(
            MockERC20(address(dai)),
            MockERC20(address(usdc))
        );
        pcvSwapper.mockSetExchangeRate(1e6); /// set dai->usdc exchange rate

        mgov = new MarketGovernance(coreAddress);

        vm.startPrank(addresses.governorAddress);

        mgov.setProfitToVconRatio(venue, profitToVconRatio);

        core.grantPCVController(address(mgov));
        core.grantLocker(address(mgov));

        address[] memory swapper = new address[](1);
        swapper[0] = address(pcvSwapper);
        mgov.addPCVSwappers(swapper);

        vm.stopPrank();
    }

    function _initializeVenues() private {
        mgov.initializeVenue(address(pcvDepositDai));
        mgov.initializeVenue(address(pcvDepositUsdc));

        pcvDepositUsdc.setLastRecordedProfit(10_000e18);
        pcvDepositDai.setLastRecordedProfit(10_000e18);
    }

    function testMarketGovernanceSetup() public {
        assertEq(address(mgov.core()), coreAddress);

        assertEq(mgov.profitToVconRatio(address(0)), 0);
        assertEq(mgov.profitToVconRatio(venue), profitToVconRatio);

        assertTrue(core.isLocker(address(mgov)));
        assertTrue(core.isPCVController(address(mgov)));
    }

    /// steps:
    //// define mock swapper
    //// add dai -> usdc and usdc -> dai routes to mgov contract

    function testSystemOneUser() public {
        _initializeVenues();

        dai.mint(address(pcvDepositDai), daiDepositAmount);
        usdc.mint(address(pcvDepositUsdc), usdcDepositAmount);

        entry.deposit(address(pcvDepositDai));
        entry.deposit(address(pcvDepositUsdc));

        vcon.mint(address(this), vconDepositAmount);

        vcon.approve(address(mgov), vconDepositAmount);
        mgov.deposit(
            vconDepositAmount,
            pcvDepositDai.balance(),
            address(pcvDepositDai),
            address(pcvDepositUsdc),
            address(pcvSwapper)
        );

        assertEq(
            pcvOracle.getTotalPcv(),
            pcvOracle.getVenueBalance(address(pcvDepositUsdc))
        );
    }

    function testSystemTwoUsers() public {
        _initializeVenues();

        uint256 totalPCV = pcvOracle.getTotalPcv();

        // console.log("dai deposit balance: ");
        // console.logInt(mgov.getVenueBalance(address(pcvDepositDai), totalPCV));

        // console.log("usdc deposit balance: ");
        // console.logInt(mgov.getVenueBalance(address(pcvDepositUsdc), totalPCV));

        testSystemOneUser();

        totalPCV = pcvOracle.getTotalPcv();

        // console.log("dai deposit balance: ");
        // console.logInt(mgov.getVenueBalance(address(pcvDepositDai), totalPCV));

        // console.log("usdc deposit balance: ");
        // console.logInt(mgov.getVenueBalance(address(pcvDepositUsdc), totalPCV));

        address user = address(1000);

        vm.startPrank(user);

        vcon.mint(user, vconDepositAmount);
        vcon.approve(address(mgov), vconDepositAmount);
        mgov.deposit(
            vconDepositAmount,
            pcvDepositUsdc.balance() / 2,
            address(pcvDepositUsdc),
            address(pcvDepositDai),
            address(pcvSwapper)
        );

        vm.stopPrank();

        assertEq(vcon.balanceOf(user), 0);
        assertEq(
            pcvOracle.getTotalPcv() / 2,
            pcvOracle.getVenueBalance(address(pcvDepositUsdc))
        );
        assertEq(
            pcvOracle.getTotalPcv() / 2,
            pcvOracle.getVenueBalance(address(pcvDepositDai))
        );
    }

    function testSystemThreeUsersLastNoDeposit(uint120 vconAmount) public {
        _initializeVenues();

        vm.assume(vconAmount > 1e9);
        testSystemTwoUsers();

        address user = address(1001);

        uint256 startingTotalSupply = mgov.totalSupply();

        vm.startPrank(user);

        vcon.mint(user, vconAmount);
        vcon.approve(address(mgov), vconAmount);
        mgov.depositNoMove(address(pcvDepositUsdc), vconAmount);

        vm.stopPrank();

        assertEq(vcon.balanceOf(user), 0);

        uint256 endingTotalSupply = mgov.totalSupply();
        uint256 totalPCV = pcvOracle.getTotalPcv();

        // console.log("\nvenue balance usdc");
        // console.logInt(mgov.getVenueBalance(address(pcvDepositUsdc), totalPCV));
        // console.log("------------------\n");

        // console.log("\nvenue balance dai");
        // console.logInt(mgov.getVenueBalance(address(pcvDepositDai), totalPCV));
        // console.log("------------------\n");

        assertEq(endingTotalSupply, startingTotalSupply + vconAmount);
        assertTrue(mgov.getVenueBalance(address(pcvDepositUsdc), totalPCV) < 0); /// underweight USDC balance
        assertTrue(mgov.getVenueBalance(address(pcvDepositDai), totalPCV) > 0); /// overweight DAI balance
    }

    function testSystemThreeUsersLastNoDepositIndividual() public {
        _initializeVenues();

        uint120 vconAmount = 1e9;

        testSystemTwoUsers();

        address user = address(1001);

        uint256 startingTotalSupply = mgov.totalSupply();

        vm.startPrank(user);

        vcon.mint(user, vconAmount);
        vcon.approve(address(mgov), vconAmount);
        mgov.depositNoMove(address(pcvDepositUsdc), vconAmount);

        vm.stopPrank();

        assertEq(vcon.balanceOf(user), 0);

        uint256 endingTotalSupply = mgov.totalSupply();
        uint256 totalPCV = pcvOracle.getTotalPcv();

        // console.log("\nvenue balance usdc");
        // console.logInt(mgov.getVenueBalance(address(pcvDepositUsdc), totalPCV));
        // console.log("------------------\n");

        // console.log("\nvenue balance dai");
        // console.logInt(mgov.getVenueBalance(address(pcvDepositDai), totalPCV));
        // console.log("------------------\n");

        assertEq(endingTotalSupply, startingTotalSupply + vconAmount);
        assertTrue(mgov.getVenueBalance(address(pcvDepositUsdc), totalPCV) < 0); /// underweight USDC balance
        assertTrue(mgov.getVenueBalance(address(pcvDepositDai), totalPCV) > 0); /// overweight DAI balance
    }

    function testUserDepositsNoMove(uint120 vconAmount) public {
        _initializeVenues();

        vm.assume(vconAmount > 1e9);

        address user = address(1001);

        uint256 startingTotalSupply = mgov.totalSupply();

        vm.startPrank(user);

        vcon.mint(user, vconAmount);
        vcon.approve(address(mgov), vconAmount);
        mgov.depositNoMove(address(pcvDepositUsdc), vconAmount);

        vm.stopPrank();

        assertEq(vcon.balanceOf(user), 0);

        uint256 endingTotalSupply = mgov.totalSupply();
        uint256 totalPCV = pcvOracle.getTotalPcv();

        assertEq(endingTotalSupply, startingTotalSupply + vconAmount);
        assertTrue(mgov.getVenueBalance(address(pcvDepositUsdc), totalPCV) < 0); /// underweight USDC
        assertTrue(mgov.getVenueBalance(address(pcvDepositDai), totalPCV) > 0); /// overweight DAI
    }

    function testUserDepositsFailsNotInitialized() public {
        mgov.initializeVenue(address(pcvDepositUsdc));

        address user = address(1001);
        uint120 vconAmount = 1e18;

        vm.startPrank(user);
        vcon.mint(user, vconAmount);
        vcon.approve(address(mgov), vconAmount);
        mgov.depositNoMove(address(pcvDepositUsdc), vconAmount);
        vm.stopPrank();

        vm.expectRevert("MarketGovernance: venue not initialized");
        mgov.deposit(
            vconAmount,
            1e18,
            address(pcvDepositUsdc),
            address(pcvDepositDai),
            address(pcvSwapper)
        );

        vm.expectRevert("MarketGovernance: venue not initialized");
        mgov.depositNoMove(address(pcvDepositDai), vconAmount);
    }

    /// todo test withdrawing
    /// todo test depositing fails when venue not initialized
    /// todo test withdrawing when there are profits
    /// todo test withdrawing when there are losses
}

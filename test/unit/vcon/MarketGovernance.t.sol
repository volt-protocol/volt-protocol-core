pragma solidity 0.8.13;

import {console} from "@forge-std/console.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {PCVRouter} from "@voltprotocol/pcv/PCVRouter.sol";
import {MockPCVSwapper} from "@test/mock/MockPCVSwapper.sol";
import {SystemUnitTest} from "@test/unit/system/System.t.sol";
import {MockPCVDepositV3} from "@test/mock/MockPCVDepositV3.sol";
import {MarketGovernance} from "@voltprotocol/vcon/MarketGovernance.sol";
import {IMarketGovernance} from "@voltprotocol/vcon/IMarketGovernance.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";

contract UnitTestMarketGovernance is SystemUnitTest {
    MarketGovernance public mgov;
    MockPCVSwapper public pcvSwapper;

    address public venue = address(10); /// a in hex
    uint256 public profitToVconRatio = 5; /// for each 1 wei in profit, 5 wei of vcon is received
    uint256 public daiDepositAmount = 1_000_000e18;
    uint256 public usdcDepositAmount = 1_000_000e6;

    uint256 public vconDepositAmount = 1_000_000e18;
    address userOne = address(1000);
    address userTwo = address(1001);

    function setUp() public override {
        super.setUp();

        /// can only swap from dai to usdc
        pcvSwapper = new MockPCVSwapper(
            MockERC20(address(dai)),
            MockERC20(address(usdc))
        );
        pcvSwapper.mockSetExchangeRate(1e6); /// set dai->usdc exchange rate

        pcvRouter = new PCVRouter(coreAddress);

        mgov = new MarketGovernance(coreAddress, address(pcvRouter));

        vm.startPrank(addresses.governorAddress);

        mgov.setProfitToVconRatio(venue, profitToVconRatio);

        core.grantPCVController(address(mgov));
        core.grantLocker(address(mgov));

        address[] memory swapper = new address[](1);
        swapper[0] = address(pcvSwapper);

        pcvRouter.addPCVSwappers(swapper);

        core.createRole(VoltRoles.PCV_MOVER, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.PCV_MOVER, address(mgov));

        vm.stopPrank();
    }

    function _initializeVenues() private {
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
        mgov.stake(vconDepositAmount, address(pcvDepositUsdc));

        IMarketGovernance.Rebalance[]
            memory balance = new IMarketGovernance.Rebalance[](1);
        balance[0] = IMarketGovernance.Rebalance({
            source: address(pcvDepositDai),
            destination: address(pcvDepositUsdc),
            swapper: address(pcvSwapper),
            amountPcv: pcvDepositDai.balance()
        });
        mgov.rebalance(balance);

        assertEq(
            pcvOracle.getTotalPcv(),
            pcvOracle.getVenueBalance(address(pcvDepositUsdc))
        );

        assertEq(
            mgov.venueVconDeposited(address(pcvDepositUsdc)),
            vconDepositAmount
        );

        assertEq(mgov.vconStaked(), vconDepositAmount);
    }

    function testSystemTwoUsers() public {
        uint256 totalPCV = pcvOracle.getTotalPcv();

        testSystemOneUser();

        totalPCV = pcvOracle.getTotalPcv();

        vm.startPrank(userOne);

        vcon.mint(userOne, vconDepositAmount);
        vcon.approve(address(mgov), vconDepositAmount);
        mgov.stake(vconDepositAmount, address(pcvDepositDai));
        IMarketGovernance.Rebalance[]
            memory balance = new IMarketGovernance.Rebalance[](1);
        balance[0] = IMarketGovernance.Rebalance({
            source: address(pcvDepositUsdc),
            destination: address(pcvDepositDai),
            swapper: address(pcvSwapper),
            amountPcv: pcvDepositUsdc.balance() / 2
        });
        mgov.rebalance(balance);

        vm.stopPrank();

        assertEq(vcon.balanceOf(userOne), 0);
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
        vm.assume(vconAmount > 1e9);
        testSystemTwoUsers();

        uint256 startingTotalSupply = mgov.vconStaked();
        uint256 startingVconStaked = mgov.venueVconDeposited(
            address(pcvDepositUsdc)
        );

        vm.startPrank(userTwo);

        vcon.mint(userTwo, vconAmount);
        vcon.approve(address(mgov), vconAmount);
        mgov.stake(vconAmount, address(pcvDepositUsdc));

        vm.stopPrank();

        assertEq(vcon.balanceOf(userTwo), 0);
        assertEq(
            mgov.venueVconDeposited(address(pcvDepositUsdc)),
            vconAmount + startingVconStaked
        );
        assertEq(
            mgov.venueUserDepositedVcon(address(pcvDepositUsdc), userTwo),
            vconAmount
        );

        uint256 endingTotalSupply = mgov.vconStaked();
        uint256 totalPCV = pcvOracle.getTotalPcv();

        assertEq(endingTotalSupply, startingTotalSupply + vconAmount);
        assertTrue(
            mgov.getVenueDeviation(address(pcvDepositUsdc), totalPCV) < 0
        ); /// underweight USDC balance
        assertTrue(
            mgov.getVenueDeviation(address(pcvDepositDai), totalPCV) > 0
        ); /// overweight DAI balance
    }

    function testSystemThreeUsersLastNoDepositIndividual() public {
        testSystemTwoUsers();

        uint120 vconAmount = 1e9;
        address user = address(1001);
        uint256 startingTotalSupply = mgov.vconStaked();

        vm.startPrank(user);

        vcon.mint(user, vconAmount);
        vcon.approve(address(mgov), vconAmount);
        mgov.stake(vconAmount, address(pcvDepositUsdc));

        vm.stopPrank();

        uint256 endingTotalSupply = mgov.vconStaked();
        uint256 totalPCV = pcvOracle.getTotalPcv();

        assertEq(vcon.balanceOf(user), 0);
        assertEq(endingTotalSupply, startingTotalSupply + vconAmount);
        assertTrue(
            mgov.getVenueDeviation(address(pcvDepositUsdc), totalPCV) < 0
        ); /// underweight USDC balance
        assertTrue(
            mgov.getVenueDeviation(address(pcvDepositDai), totalPCV) > 0
        ); /// overweight DAI balance
    }

    function testUserDepositsNoMove(uint120 vconAmount) public {
        vm.assume(vconAmount > 1e9);

        _initializeVenues();

        address user = address(1001);
        uint256 startingTotalSupply = mgov.vconStaked();

        vm.startPrank(user);
        vcon.mint(user, vconAmount);
        vcon.approve(address(mgov), vconAmount);
        mgov.stake(vconAmount, address(pcvDepositUsdc));
        vm.stopPrank();

        uint256 endingTotalSupply = mgov.vconStaked();
        uint256 totalPCV = pcvOracle.getTotalPcv();

        assertEq(vcon.balanceOf(user), 0);
        assertEq(endingTotalSupply, startingTotalSupply + vconAmount);
        assertTrue(
            mgov.getVenueDeviation(address(pcvDepositUsdc), totalPCV) < 0
        ); /// underweight USDC
        assertTrue(
            mgov.getVenueDeviation(address(pcvDepositDai), totalPCV) > 0
        ); /// overweight DAI
    }

    // function testUserDepositsFailsNotInitialized() public {
    //     address user = address(1001);
    //     uint120 vconAmount = 1e18;

    //     vm.startPrank(user);
    //     vcon.mint(user, vconAmount);
    //     vcon.approve(address(mgov), vconAmount);
    //     mgov.stake(
    //         vconAmount,
    //         0,
    //         address(pcvDepositDai),
    //         address(pcvDepositUsdc),
    //         address(pcvSwapper)
    //     );
    //     vm.stopPrank();

    //     vm.expectRevert("MarketGovernance: venue not initialized");
    //     mgov.stake(
    //         vconAmount,
    //         1e18,
    //         address(pcvDepositUsdc),
    //         address(pcvDepositDai),
    //         address(pcvSwapper)
    //     );

    //     vm.expectRevert("MarketGovernance: venue not initialized");
    //     mgov.stake(
    //         vconAmount,
    //         0, /// deposit no pcv, meaning things will be imbalanced
    //         address(pcvDepositUsdc),
    //         address(pcvDepositDai),
    //         address(pcvSwapper)
    //     );
    // }

    function testUnstakingOneUser() public {
        testSystemOneUser();

        assertEq(vcon.balanceOf(address(this)), 0);
        uint256 vconAmount = mgov.vconStaked();

        mgov.unstake(
            vconAmount,
            address(pcvDepositUsdc),
            address(pcvDepositDai),
            address(pcvSwapper),
            address(this)
        );

        assertEq(vcon.balanceOf(address(this)), vconAmount);

        /// all funds moved to DAI PCV deposit
        assertEq(
            pcvOracle.getTotalPcv(),
            pcvOracle.getVenueBalance(address(pcvDepositDai))
        );
        assertEq(0, mgov.venueVconDeposited(address(pcvDepositDai)));

        assertEq(0, pcvOracle.getVenueBalance(address(pcvDepositUsdc)));
        assertEq(0, mgov.venueVconDeposited(address(pcvDepositUsdc)));

        assertEq(0, mgov.vconStaked());
    }

    function testUnstakingTwoUsers() public {
        testSystemTwoUsers();

        assertEq(vcon.balanceOf(address(this)), 0);

        uint256 startingVconStakedAmount = mgov.vconStaked();
        uint256 vconAmount = mgov.venueUserDepositedVcon(
            address(pcvDepositUsdc),
            address(this)
        );

        mgov.unstake(
            vconAmount,
            address(pcvDepositUsdc),
            address(pcvDepositDai),
            address(pcvSwapper),
            address(this)
        );

        assertEq(vcon.balanceOf(address(this)), vconAmount);

        /// all funds moved to DAI PCV deposit
        assertEq(
            pcvOracle.getTotalPcv(),
            pcvOracle.getVenueBalance(address(pcvDepositDai))
        );
        assertEq(startingVconStakedAmount - vconAmount, mgov.vconStaked());

        assertEq(0, pcvOracle.getVenueBalance(address(pcvDepositUsdc)));
        assertEq(0, mgov.venueVconDeposited(address(pcvDepositUsdc)));

        // assertEq(vconAmount - startingVconStakedAmount, mgov.vconStaked());
    }

    /// test withdrawing when src and dest are equal
    function testWithdrawFailsSrcDestEqual() public {
        uint256 vconAmount = mgov.vconStaked();

        vm.expectRevert("MarketGovernance: src and dest equal");
        mgov.unstake(
            vconAmount,
            address(pcvDepositUsdc),
            address(pcvDepositUsdc),
            address(0),
            address(this)
        );
    }

    /// todo test withdrawing
    /// todo test depositing fails when venue not initialized
    /// todo test withdrawing when there are profits
    /// todo test withdrawing when there are losses
}

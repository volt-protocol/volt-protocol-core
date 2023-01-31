pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {console} from "@forge-std/console.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {PCVRouter} from "@voltprotocol/pcv/PCVRouter.sol";
import {MockPCVSwapper} from "@test/mock/MockPCVSwapper.sol";
import {SystemUnitTest} from "@test/unit/system/System.t.sol";
import {MockPCVDepositV3} from "@test/mock/MockPCVDepositV3.sol";
import {MarketGovernance} from "@voltprotocol/vcon/MarketGovernance.sol";
import {IMarketGovernance} from "@voltprotocol/vcon/IMarketGovernance.sol";
import {ERC20HoldingPCVDeposit} from "@test/mock/ERC20HoldingPCVDeposit.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";

contract UnitTestMarketGovernance is SystemUnitTest {
    using SafeCast for *;

    MarketGovernance public mgov;
    MockPCVSwapper public pcvSwapper;
    ERC20HoldingPCVDeposit public daiHoldingDeposit;
    ERC20HoldingPCVDeposit public usdcHoldingDeposit;

    uint256 public profitToVconRatioUsdc = 5e12; /// for each 1 wei in profit, 5e12 wei of vcon is received
    uint256 public profitToVconRatioDai = 5; /// for each 1 wei in profit, 5 wei of vcon is received
    uint256 public daiDepositAmount = 1_000_000e18;
    uint256 public usdcDepositAmount = 1_000_000e6;

    uint256 public vconDepositAmount = 1_000_000e18;
    address userOne = address(1000);
    address userTwo = address(1001);

    /// @notice emitted when profit to vcon ratio is updated
    event ProfitToVconRatioUpdated(
        address indexed venue,
        uint256 oldRatio,
        uint256 newRatio
    );

    /// @notice emitted when the router is updated
    event PCVRouterUpdated(
        address indexed oldPcvRouter,
        address indexed newPcvRouter
    );

    function setUp() public override {
        super.setUp();

        daiHoldingDeposit = new ERC20HoldingPCVDeposit(
            coreAddress,
            IERC20(address(dai)),
            address(0)
        );
        usdcHoldingDeposit = new ERC20HoldingPCVDeposit(
            coreAddress,
            IERC20(address(usdc)),
            address(0)
        );

        /// can only swap from dai to usdc
        pcvSwapper = new MockPCVSwapper(
            MockERC20(address(dai)),
            MockERC20(address(usdc))
        );
        pcvSwapper.mockSetExchangeRate(1e6); /// set dai->usdc exchange rate

        pcvRouter = new PCVRouter(coreAddress);

        mgov = new MarketGovernance(coreAddress, address(pcvRouter));

        vm.startPrank(addresses.governorAddress);

        core.grantPCVController(address(mgov));
        core.grantLocker(address(mgov));
        core.grantLocker(address(daiHoldingDeposit));
        core.grantLocker(address(usdcHoldingDeposit));

        address[] memory swapper = new address[](1);
        swapper[0] = address(pcvSwapper);

        pcvRouter.addPCVSwappers(swapper);

        core.createRole(VoltRoles.PCV_MOVER, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.PCV_MOVER, address(mgov));

        address[] memory venuesToAdd = new address[](2);
        venuesToAdd[0] = address(daiHoldingDeposit);
        venuesToAdd[1] = address(usdcHoldingDeposit);

        address[] memory oraclesToAdd = new address[](2);
        oraclesToAdd[0] = address(daiConstantOracle);
        oraclesToAdd[1] = address(usdcConstantOracle);

        pcvOracle.addVenues(venuesToAdd, oraclesToAdd);

        mgov.setProfitToVconRatio(address(pcvDepositDai), profitToVconRatioDai);
        mgov.setProfitToVconRatio(
            address(pcvDepositUsdc),
            profitToVconRatioUsdc
        );

        mgov.setUnderlyingTokenHolderDeposit(
            address(dai),
            address(daiHoldingDeposit)
        );
        mgov.setUnderlyingTokenHolderDeposit(
            address(usdc),
            address(usdcHoldingDeposit)
        );

        vm.stopPrank();
    }

    function _initializeVenues() private {
        pcvDepositUsdc.setLastRecordedProfit(10_000e6);
        pcvDepositDai.setLastRecordedProfit(10_000e18);
    }

    function testMarketGovernanceSetup() public {
        assertEq(address(mgov.core()), coreAddress);

        assertEq(mgov.profitToVconRatio(address(0)), 0);
        assertEq(
            mgov.profitToVconRatio(address(pcvDepositDai)),
            profitToVconRatioDai
        );
        assertEq(
            mgov.profitToVconRatio(address(pcvDepositUsdc)),
            profitToVconRatioUsdc
        );

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
            mgov.venueTotalShares(address(pcvDepositUsdc)),
            vconDepositAmount
        );

        assertEq(mgov.getTotalVconStaked(), vconDepositAmount);
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

        uint256 startingTotalSupply = mgov.getTotalVconStaked();
        uint256 startingVconStaked = mgov.venueTotalShares(
            address(pcvDepositUsdc)
        );

        vm.startPrank(userTwo);

        vcon.mint(userTwo, vconAmount);
        vcon.approve(address(mgov), vconAmount);
        mgov.stake(vconAmount, address(pcvDepositUsdc));

        vm.stopPrank();

        assertEq(vcon.balanceOf(userTwo), 0);
        assertEq(
            mgov.venueTotalShares(address(pcvDepositUsdc)),
            vconAmount + startingVconStaked
        );
        assertEq(
            mgov.venueUserShares(address(pcvDepositUsdc), userTwo),
            vconAmount
        );

        uint256 endingTotalSupply = mgov.getTotalVconStaked();
        uint256 totalPCV = pcvOracle.getTotalPcv();

        assertEq(endingTotalSupply, startingTotalSupply + vconAmount);
        assertTrue(
            mgov.getVenueDeviation(
                address(pcvDepositUsdc),
                totalPCV,
                endingTotalSupply
            ) < 0
        ); /// underweight USDC balance
        assertTrue(
            mgov.getVenueDeviation(
                address(pcvDepositDai),
                totalPCV,
                endingTotalSupply
            ) > 0
        ); /// overweight DAI balance
    }

    function testSystemThreeUsersLastNoDepositIndividual() public {
        testSystemTwoUsers();

        uint120 vconAmount = 1e9;
        address user = address(1001);
        uint256 startingTotalSupply = mgov.getTotalVconStaked();

        vm.startPrank(user);

        vcon.mint(user, vconAmount);
        vcon.approve(address(mgov), vconAmount);
        mgov.stake(vconAmount, address(pcvDepositUsdc));

        vm.stopPrank();

        uint256 endingTotalSupply = mgov.getTotalVconStaked();
        uint256 totalPCV = pcvOracle.getTotalPcv();

        assertEq(vcon.balanceOf(user), 0);
        assertEq(endingTotalSupply, startingTotalSupply + vconAmount);
        assertTrue(
            mgov.getVenueDeviation(
                address(pcvDepositUsdc),
                totalPCV,
                endingTotalSupply
            ) < 0
        ); /// underweight USDC balance in venues compared to staked vcon
        assertTrue(
            mgov.getVenueDeviation(
                address(pcvDepositDai),
                totalPCV,
                endingTotalSupply
            ) > 0
        ); /// overweight DAI balance in venues compared to staked vcon
    }

    function testUserDepositsNoMove(uint120 vconAmount) public {
        vm.assume(vconAmount > 1e9);

        _initializeVenues();

        address user = address(1001);
        uint256 startingTotalSupply = mgov.getTotalVconStaked();

        vm.startPrank(user);
        vcon.mint(user, vconAmount);
        vcon.approve(address(mgov), vconAmount);
        mgov.stake(vconAmount, address(pcvDepositUsdc));
        vm.stopPrank();

        uint256 endingTotalSupply = mgov.getTotalVconStaked();
        uint256 totalPCV = pcvOracle.getTotalPcv();

        assertEq(vcon.balanceOf(user), 0);
        assertEq(endingTotalSupply, startingTotalSupply + vconAmount);
        assertTrue(
            mgov.getVenueDeviation(
                address(pcvDepositUsdc),
                totalPCV,
                endingTotalSupply
            ) < 0
        ); /// underweight USDC
        assertTrue(
            mgov.getVenueDeviation(
                address(pcvDepositDai),
                totalPCV,
                endingTotalSupply
            ) > 0
        ); /// overweight DAI
    }

    function testUnstakingOneUserOneWei() public {
        testSystemOneUser();

        assertEq(vcon.balanceOf(address(this)), 0);
        /// subtract 1 to counter the addition the protocol does
        uint256 startingShareAmount = mgov.venueUserShares(
            address(pcvDepositUsdc),
            address(this)
        );

        mgov.unstake(
            startingShareAmount,
            address(pcvDepositUsdc),
            address(this)
        );

        assertEq(vcon.balanceOf(address(this)), startingShareAmount);

        assertEq(
            0,
            mgov.venueUserShares(address(pcvDepositUsdc), address(this))
        );
    }

    function testUnstakingOneUser() public {
        testSystemOneUser();

        assertEq(vcon.balanceOf(address(this)), 0);
        uint256 shareAmount = mgov.venueUserShares(
            address(pcvDepositUsdc),
            address(this)
        );
        uint256 vconAmount = mgov.sharesToVcon(
            address(pcvDepositUsdc),
            shareAmount
        );

        mgov.unstake(shareAmount, address(pcvDepositUsdc), address(this));

        assertEq(vcon.balanceOf(address(this)), vconAmount);

        /// all funds moved to DAI Holding PCV deposit
        assertEq(
            pcvOracle.getTotalPcv(),
            pcvOracle.getVenueBalance(address(usdcHoldingDeposit))
        );
        assertEq(0, mgov.venueTotalShares(address(pcvDepositDai)));
        assertEq(0, mgov.venueTotalShares(address(pcvDepositUsdc)));
        assertEq(0, pcvOracle.getVenueBalance(address(pcvDepositUsdc)));

        assertEq(0, mgov.getTotalVconStaked());
    }

    function testUnstakingTwoUsers() public {
        testSystemTwoUsers();

        assertEq(vcon.balanceOf(address(this)), 0);

        uint256 vconAmount = mgov.venueUserShares(
            address(pcvDepositUsdc),
            address(this)
        );

        mgov.unstake(vconAmount, address(pcvDepositUsdc), address(this));

        assertEq(vcon.balanceOf(address(this)), vconAmount);

        {
            assertEq(0, vcon.balanceOf(userOne));

            uint256 shareAmount = mgov.venueUserShares(
                address(pcvDepositDai),
                userOne
            );
            vm.startPrank(userOne);
            mgov.unstake(shareAmount, address(pcvDepositDai), userOne);

            assertEq(
                mgov.sharesToVcon(address(pcvDepositDai), shareAmount),
                vcon.balanceOf(userOne)
            );
        }

        /// half of funds moved to DAI PCV deposit
        assertEq(
            pcvOracle.getTotalPcv() / 2,
            pcvOracle.getVenueBalance(address(usdcHoldingDeposit))
        );

        /// half of funds moved to DAI PCV deposit
        assertEq(
            pcvOracle.getTotalPcv() / 2,
            pcvOracle.getVenueBalance(address(daiHoldingDeposit))
        );
        assertEq(0, mgov.getTotalVconStaked());

        assertEq(0, pcvOracle.getVenueBalance(address(pcvDepositUsdc)));
        assertEq(0, mgov.venueTotalShares(address(pcvDepositUsdc)));
    }

    struct DepositInfo {
        address user;
        uint120 vconAmount;
        uint8 venue;
    }

    function testMultipleUsersStake(DepositInfo[] memory users) public {
        unchecked {
            for (uint256 i = 0; i < users.length; i++) {
                address user = users[i].user;
                if (user == address(0)) {
                    /// do not allow 0 address user
                    users[i].user = address(
                        uint160(block.timestamp + block.number + i)
                    );
                }
            }
        }

        uint256 totalPcv = pcvOracle.getTotalPcv();
        uint256 totalVconStaked = 0;
        uint256 daiVconStaked = 0;
        uint256 usdcVconStaked = 0;

        unchecked {
            for (uint256 i = 0; i < users.length; i++) {
                address user = users[i].user;
                uint256 amount = users[i].vconAmount;
                totalVconStaked += amount;

                vcon.mint(user, amount);

                vm.startPrank(user);
                vcon.approve(address(mgov), amount);

                if (users[i].venue % 2 == 0) {
                    daiVconStaked += amount;
                    mgov.stake(amount, address(pcvDepositDai));
                } else {
                    usdcVconStaked += amount;
                    mgov.stake(amount, address(pcvDepositUsdc));
                }
            }
        }

        int256 daiAmount = mgov.getVenueDeviation(
            address(pcvDepositDai),
            totalPcv,
            totalVconStaked
        );

        IMarketGovernance.Rebalance[]
            memory balance = new IMarketGovernance.Rebalance[](1);

        if (daiAmount > 0) {
            /// over allocated DAI
            balance[0] = IMarketGovernance.Rebalance({
                source: address(pcvDepositDai),
                destination: address(pcvDepositUsdc),
                swapper: address(pcvSwapper),
                amountPcv: daiAmount.toUint256()
            });
        } else {
            /// under allocated DAI
            balance[0] = IMarketGovernance.Rebalance({
                source: address(pcvDepositUsdc),
                destination: address(pcvDepositDai),
                swapper: address(pcvSwapper),
                amountPcv: daiAmount.toUint256() / 1e12
            });
        }

        mgov.rebalance(balance);

        // assertEq(mgov.getVenueDeviation(address(pcvDepositDai), totalPcv, totalVconStaked), 0);
        // assertEq(mgov.getVenueDeviation(address(pcvDepositUsdc), totalPcv, totalVconStaked), 0);
    }

    /// Gain and loss scenarios

    function testWithdrawWithGains() public {
        uint120 vconAmount = 1000e18;
        testSystemThreeUsersLastNoDeposit(vconAmount);

        pcvDepositUsdc.setLastRecordedProfit(20_000e6);
        pcvDepositDai.setLastRecordedProfit(20_000e18);

        /// how much VCON is owed?
        uint256 vconOwedUsdcRewards = 10_000e6 * profitToVconRatioUsdc;
        uint256 vconOwedDaiRewards = 10_000e18 * profitToVconRatioDai;

        uint256 totalVconRewardsOwed = vconOwedUsdcRewards + vconOwedDaiRewards;
        vcon.mint(address(mgov), totalVconRewardsOwed);

        uint256 startingVconBalance = vcon.balanceOf(address(this));
        uint256 shareAmount = mgov.venueUserShares(
            address(pcvDepositUsdc),
            address(this)
        );

        mgov.unstake(shareAmount, address(pcvDepositUsdc), address(this));

        uint256 endingVconBalance = vcon.balanceOf(address(this));

        assertTrue(endingVconBalance > startingVconBalance);
    }

    function testWithdrawWithLossesFailsDai() public {
        uint120 vconAmount = 1000e18;
        testSystemThreeUsersLastNoDeposit(vconAmount);
        pcvDepositDai.setLastRecordedProfit(0);

        uint256 shareAmount = mgov.venueUserShares(
            address(pcvDepositDai),
            address(this)
        );

        vm.expectRevert("MarketGovernance: loss scenario");
        mgov.unstake(shareAmount, address(pcvDepositDai), address(this));
    }

    function testWithdrawWithLossesFailsUsdc() public {
        uint120 vconAmount = 1000e18;
        testSystemThreeUsersLastNoDeposit(vconAmount);
        pcvDepositUsdc.setLastRecordedProfit(0);

        uint256 shareAmount = mgov.venueUserShares(
            address(pcvDepositUsdc),
            address(this)
        );

        vm.expectRevert("MarketGovernance: loss scenario");
        mgov.unstake(shareAmount, address(pcvDepositUsdc), address(this));
    }

    function testSetProfitToVconRatio(uint8 venueNumber, uint256 ratio) public {
        address venue = venueNumber % 2 == 0
            ? address(daiHoldingDeposit)
            : address(usdcHoldingDeposit);
        uint256 oldProfitToVconRatio = mgov.profitToVconRatio(venue);

        vm.expectEmit(true, true, false, true, address(mgov));
        emit ProfitToVconRatioUpdated(venue, oldProfitToVconRatio, ratio);

        vm.prank(addresses.governorAddress);
        mgov.setProfitToVconRatio(venue, ratio);

        assertEq(mgov.profitToVconRatio(venue), ratio);
    }

    function testSetPCVRouter(address newRouter) public {
        address oldPCVRouter = mgov.pcvRouter();

        vm.expectEmit(true, true, false, true, address(mgov));
        emit PCVRouterUpdated(oldPCVRouter, newRouter);

        vm.prank(addresses.governorAddress);
        mgov.setPCVRouter(newRouter);

        assertEq(mgov.pcvRouter(), newRouter);
    }

    /// todo test withdrawing
    /// todo test withdrawing when there are profits
    /// todo test withdraw failing when there are losses

    /// todo test stake, unstake, rebalance, accrueVcon, realize gains
    /// and losses with invalid venues to ensure reverts
    function testStakeInvalidVenueFails() public {
        vm.expectRevert("MarketGovernance: invalid destination");
        mgov.stake(0, address(0));
    }

    function testAccrueInvalidVenueFails() public {
        vm.expectRevert("MarketGovernance: invalid destination");
        mgov.accrueVcon(address(0));
    }

    function testAccrueInLossVenueFails() public {
        pcvDepositDai.setLastRecordedProfit(20_000e18);
        mgov.accrueVcon(address(pcvDepositDai));

        pcvDepositDai.setLastRecordedProfit(0);

        vm.expectRevert("MarketGovernance: loss scenario");
        mgov.accrueVcon(address(pcvDepositDai));
    }

    function testSetProfitToVconRatioFailsInvalidVenue() public {
        vm.expectRevert("MarketGovernance: invalid venue");
        vm.prank(addresses.governorAddress);
        mgov.setProfitToVconRatio(address(0), 0);
    }

    function testUnstakeInvalidSourceVenueFails() public {
        vm.expectRevert("MarketGovernance: invalid source");
        mgov.unstake(0, address(0), address(0));
    }

    function testSetUnderlyingDepositFailsUnderlyingMismatch() public {
        vm.expectRevert("MarketGovernance: underlying mismatch");
        vm.prank(addresses.governorAddress);
        mgov.setUnderlyingTokenHolderDeposit(
            address(usdc),
            address(daiHoldingDeposit)
        );
    }

    function testSetUnderlyingDepositFailsInvalidVenue() public {
        vm.expectRevert("MarketGovernance: invalid venue");
        vm.prank(addresses.governorAddress);
        mgov.setUnderlyingTokenHolderDeposit(address(usdc), address(0));
    }

    /// ACL tests
    function testSetProfitToVconRatioFailsNonGovernor() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        mgov.setProfitToVconRatio(address(0), 0);
    }

    function testSetPCVRouterFailsNonGovernor() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        mgov.setPCVRouter(address(0));
    }

    function testSetUnderlyingDepositFailsNonGovernor() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        mgov.setUnderlyingTokenHolderDeposit(
            address(dai),
            address(daiHoldingDeposit)
        );
    }

    //// Pause tests

    function testPause() public {
        vm.prank(addresses.governorAddress);
        mgov.pause();

        assertTrue(mgov.paused());
    }

    function testRebalanceFailsWhenPaused() public {
        testPause();

        IMarketGovernance.Rebalance[]
            memory balance = new IMarketGovernance.Rebalance[](1);
        balance[0] = IMarketGovernance.Rebalance({
            source: address(pcvDepositDai),
            destination: address(pcvDepositUsdc),
            swapper: address(pcvSwapper),
            amountPcv: pcvDepositDai.balance()
        });
        vm.expectRevert("Pausable: paused");

        mgov.rebalance(balance);
    }

    function testStakingFailsWhenPaused() public {
        testPause();

        vm.expectRevert("Pausable: paused");
        mgov.stake(0, address(0));
    }

    function testUnstakingFailsWhenPaused() public {
        testPause();

        vm.expectRevert("Pausable: paused");
        mgov.unstake(0, address(0), address(this));
    }

    function testAccrueFailsWhenPaused() public {
        testPause();

        vm.expectRevert("Pausable: paused");
        mgov.accrueVcon(address(0));
    }
}

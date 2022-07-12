// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {MockPCVDepositV2} from "../../mock/MockPCVDepositV2.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {ScalingPriceOracle} from "../../oracle/ScalingPriceOracle.sol";
import {MockScalingPriceOracle} from "../../mock/MockScalingPriceOracle.sol";
import {ICore} from "../../core/ICore.sol";
import {Core} from "../../core/Core.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {BasePSM} from "../../peg/BasePSM.sol";
import {VanillaPriceBoundPSM} from "../../peg/VanillaPriceBoundPSM.sol";
import {VanillaPSM} from "../../peg/VanillaPSM.sol";
import {getCore, getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";

import {Constants} from "../../Constants.sol";

contract IntegrationTestVanillaPSMTest is DSTest {
    using SafeCast for *;

    VanillaPriceBoundPSM private priceBoundPsm;
    VanillaPSM private vanillaPsm;

    ICore private core = ICore(MainnetAddresses.CORE);
    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private underlyingToken = usdc;

    address public makerUSDCPSM = MainnetAddresses.MAKER_USDC_PSM;

    uint256 public constant mintAmount = 10_000_000e6;
    uint256 public constant voltMintAmount = 10_000_000e18;

    /// @notice live FEI PCV Deposit
    ERC20CompoundPCVDeposit public immutable rariVoltPCVDeposit =
        ERC20CompoundPCVDeposit(0x0b9A7EA2FCA868C93640Dd77cF44df335095F501);

    /// @notice Oracle Pass Through contract
    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 voltFloorPrice = 9_000e12;
    uint256 voltCeilingPrice = 10_500e12;
    uint256 reservesThreshold = type(uint256).max; /// max uint so that surplus can never be allocated into the pcv deposit

    function setUp() public {
        BasePSM.OracleParams memory oracleParams;

        oracleParams = BasePSM.OracleParams({
            coreAddress: address(core),
            oracleAddress: address(oracle),
            backupOracle: address(0),
            decimalsNormalizer: 12,
            doInvert: false
        });

        /// create PSM
        priceBoundPsm = new VanillaPriceBoundPSM(
            voltFloorPrice,
            voltCeilingPrice,
            oracleParams,
            reservesThreshold,
            IERC20(address(usdc)),
            rariVoltPCVDeposit
        );

        vanillaPsm = new VanillaPSM(
            oracleParams,
            reservesThreshold,
            IERC20(address(usdc)),
            rariVoltPCVDeposit
        );

        uint256 balance = usdc.balanceOf(makerUSDCPSM);
        vm.prank(makerUSDCPSM);
        usdc.transfer(address(this), balance);

        vm.startPrank(MainnetAddresses.GOVERNOR);

        /// grant the PSM the PCV Controller role
        core.grantMinter(MainnetAddresses.GOVERNOR);
        /// mint VOLT to the user
        volt.mint(address(priceBoundPsm), voltMintAmount);
        volt.mint(address(vanillaPsm), voltMintAmount);
        volt.mint(address(this), voltMintAmount);

        vm.stopPrank();

        usdc.transfer(address(priceBoundPsm), balance / 3);
        usdc.transfer(address(vanillaPsm), balance / 3);
    }

    /// @notice PSM is set up correctly
    function testSetUpCorrectly() public {
        assertTrue(!priceBoundPsm.doInvert());
        assertTrue(priceBoundPsm.isPriceValid());
        assertEq(priceBoundPsm.floor(), voltFloorPrice);
        assertEq(priceBoundPsm.ceiling(), voltCeilingPrice);
        assertEq(address(priceBoundPsm.oracle()), address(oracle));
        assertEq(address(priceBoundPsm.backupOracle()), address(0));
        assertEq(priceBoundPsm.decimalsNormalizer(), 12);
        assertEq(address(priceBoundPsm.underlyingToken()), address(usdc));
        assertEq(priceBoundPsm.reservesThreshold(), reservesThreshold);

        assertTrue(!vanillaPsm.doInvert());
        assertEq(address(vanillaPsm.oracle()), address(oracle));
        assertEq(address(vanillaPsm.backupOracle()), address(0));
        assertEq(vanillaPsm.decimalsNormalizer(), 12);
        assertEq(address(vanillaPsm.underlyingToken()), address(usdc));
        assertEq(vanillaPsm.reservesThreshold(), reservesThreshold);
    }

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOut() public {
        uint256 amountVoltIn = 100e18;
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e6;

        assertApproxEq(
            priceBoundPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            1
        );

        assertApproxEq(
            vanillaPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            1
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOut() public {
        uint256 amountUSDCIn = 100e18;
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        uint256 amountOut = ((amountUSDCIn * 1e6) / currentPegPrice);

        assertApproxEq(
            priceBoundPsm.getMintAmountOut(amountUSDCIn).toInt256(),
            amountOut.toInt256(),
            1
        );

        assertApproxEq(
            vanillaPsm.getMintAmountOut(amountUSDCIn).toInt256(),
            amountOut.toInt256(),
            1
        );
    }

    /// @notice pcv deposit receives underlying token on mint
    function testSwapUnderlyingForVoltAfterPriceIncrease() public {
        uint256 amountStableIn = 101_000;
        uint256 amountVoltOut = priceBoundPsm.getMintAmountOut(amountStableIn);
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(priceBoundPsm)
        );

        underlyingToken.approve(address(priceBoundPsm), amountStableIn);
        priceBoundPsm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(priceBoundPsm)
        );

        assertEq(
            endingUserVoltBalance,
            startingUserVoltBalance + amountVoltOut
        );
        assertEq(
            startingPSMUnderlyingBalance + amountStableIn,
            endingPSMUnderlyingBalance
        );
    }

    /// @notice redeem fails without approval
    function testSwapVoltForUSDCFailsWithoutApproval() public {
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));

        vanillaPsm.redeem(address(this), mintAmount, mintAmount / 1e12);
    }

    /// @notice mint fails without approval
    function testSwapUnderlyingForVoltFailsWithoutApproval() public {
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));

        vanillaPsm.mint(address(this), mintAmount, 0);
    }

    /// @notice withdraw erc20 fails without correct permissions
    function testERC20WithdrawFailure() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a PCV controller"));

        vanillaPsm.withdrawERC20(address(underlyingToken), address(this), 100);
    }

    /// @notice withdraw erc20 succeeds with correct permissions
    function testERC20WithdrawSuccess() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        vanillaPsm.withdrawERC20(
            address(underlyingToken),
            address(this),
            mintAmount
        );
        uint256 endingBalance = underlyingToken.balanceOf(address(this));

        assertEq(endingBalance - startingBalance, mintAmount);
    }

    /// @notice set global rate limited minter fails when caller is governor and new address is 0
    function testSetPCVDepositFailureZeroAddress() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);

        vm.expectRevert(
            bytes("PegStabilityModule: Invalid new surplus target")
        );
        vanillaPsm.setSurplusTarget(IPCVDeposit(address(0)));

        vm.stopPrank();
    }

    /// @notice set PCV deposit fails when caller is governor and new address is 0
    function testSetPCVDepositFailureNonGovernor() public {
        vm.expectRevert(
            bytes("CoreRef: Caller is not a governor or contract admin")
        );
        vanillaPsm.setSurplusTarget(IPCVDeposit(address(0)));
    }

    /// @notice set PCV Deposit succeeds when caller is governor and underlying tokens match
    function testSetPCVDepositSuccess() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);

        MockPCVDepositV2 newPCVDeposit = new MockPCVDepositV2(
            address(core),
            address(underlyingToken),
            0,
            0
        );

        vanillaPsm.setSurplusTarget(IPCVDeposit(address(newPCVDeposit)));

        vm.stopPrank();

        assertEq(address(newPCVDeposit), address(vanillaPsm.surplusTarget()));
    }

    /// @notice redeem fails when paused
    function testRedeemFailsWhenPaused() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vanillaPsm.pause();

        vm.expectRevert(bytes("Pausable: paused"));
        vanillaPsm.redeem(address(this), 100, 100);
    }

    /// @notice mint fails when paused
    function testMintFailsWhenPaused() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vanillaPsm.pause();

        vm.expectRevert(bytes("Pausable: paused"));
        vanillaPsm.mint(address(this), 100, 100);
    }
}

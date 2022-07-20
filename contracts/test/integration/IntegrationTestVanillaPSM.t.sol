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
import {IBasePSM} from "../../peg/IBasePSM.sol";
import {VanillaPriceBoundPSM} from "../../peg/VanillaPriceBoundPSM.sol";
import {VanillaPSM} from "../../peg/VanillaPSM.sol";
import {getCore, getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {Constants} from "../../Constants.sol";

import "hardhat/console.sol";

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
    IPCVDeposit public immutable pcvDeposit =
        IPCVDeposit(MainnetAddresses.VOLT_USDC_PSM);

    /// @notice Oracle Pass Through contract
    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 voltFloorPrice = 9_000e12;
    uint256 voltCeilingPrice = 10_500e12;
    uint256 reservesThreshold = type(uint256).max; /// max uint so that surplus can never be allocated into the pcv deposit

    function setUp() public {
        BasePSM.OracleParams memory oracleParams;

        oracleParams = IBasePSM.OracleParams({
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
            pcvDeposit
        );

        vanillaPsm = new VanillaPSM(
            oracleParams,
            reservesThreshold,
            IERC20(address(usdc)),
            pcvDeposit
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
    function testSwapUnderlyingForVolt() public {
        uint256 amountStableIn = 101_000;
        uint256 amountVoltOut = vanillaPsm.getMintAmountOut(amountStableIn);
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(vanillaPsm)
        );

        underlyingToken.approve(address(vanillaPsm), amountStableIn);
        vanillaPsm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(vanillaPsm)
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

    /// @notice redeem fails without approval
    function testMintFailsWhenMintExceedsPSMBalance() public {
        underlyingToken.approve(address(vanillaPsm), type(uint256).max);

        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 psmVoltBalance = volt.balanceOf(address(vanillaPsm));

        // we get the amount we want to put in by getting the total PSM balance and dividing by the current peg price
        // this lets us get the maximum amount we can deposit
        uint256 amountIn = (psmVoltBalance * currentPegPrice) / 1e6;

        // this will revert (correctly) as the math above is less precise than the PSMs, therefore our amountIn
        // will slightly exceed the balance the PSM can give to us.
        vm.expectRevert(
            bytes("PegStabilityModule: Mint amount exceeds balance")
        );

        vanillaPsm.mint(address(this), amountIn, psmVoltBalance);
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
        IPCVDeposit surplusTarget = vanillaPsm.surplusTarget();

        vm.expectRevert(
            bytes("PegStabilityModule: Invalid new surplus target")
        );
        vanillaPsm.setSurplusTarget(surplusTarget);

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

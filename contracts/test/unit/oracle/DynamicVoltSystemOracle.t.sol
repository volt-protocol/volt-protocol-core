// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {ICoreV2} from "../../../core/ICoreV2.sol";
import {IPCVOracle} from "../../../oracle/IPCVOracle.sol";
import {DynamicVoltSystemOracle} from "../../../oracle/DynamicVoltSystemOracle.sol";
import {DynamicVoltRateModel} from "../../../oracle/DynamicVoltRateModel.sol";
import {getCoreV2} from "./../utils/Fixtures.sol";
import {TestAddresses as addresses} from "../utils/TestAddresses.sol";

contract DynamicVoltSystemOracleUnitTest is DSTest {
    ICoreV2 private core;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// @notice reference to the volt system oracle
    DynamicVoltRateModel private rateModel;
    DynamicVoltSystemOracle private systemOracle;

    uint256 public constant TIMEFRAME = 365.25 days;
    uint256 public constant initialOraclePrice = 1e18; // start price = 1.0$
    uint256 public constant periodStartTime = 1000;
    uint256 public constant baseChangeRate = 0.1e18; // 10% APR
    uint256 public lastLiquidVenuePercentage = 0.5e18; // 50% liquid reserves

    // DynamicVoltSystemOracle events
    event InterestCompounded(
        uint64 periodStartTime,
        uint192 periodStartOraclePrice
    );
    event BaseRateUpdated(
        uint256 periodStart,
        uint256 oldRate,
        uint256 newRate
    );
    event ActualRateUpdated(
        uint256 periodStart,
        uint256 oldRate,
        uint256 newRate
    );
    event RateModelUpdated(
        uint256 blockTime,
        address oldRateModel,
        address newRateModel
    );

    // mock behavior of the previous system oracle
    function getCurrentOraclePrice() external pure returns (uint256) {
        return initialOraclePrice;
    }

    function setUp() public {
        core = getCoreV2();

        rateModel = new DynamicVoltRateModel();
        systemOracle = new DynamicVoltSystemOracle(
            address(core),
            baseChangeRate,
            baseChangeRate, // actualChangeRate is 0% boosted
            uint64(periodStartTime),
            address(rateModel),
            address(this) // old volt system oracle
        );

        /// allow this contract to call in and update the actual rate
        vm.prank(addresses.governorAddress);
        core.setPCVOracle(IPCVOracle(address(this)));
    }

    function testSetup() public {
        assertEq(systemOracle.periodStartTime(), uint64(periodStartTime));
        assertEq(
            systemOracle.periodStartOraclePrice(),
            uint192(initialOraclePrice)
        );
        assertEq(systemOracle.baseChangeRate(), baseChangeRate);
        assertEq(systemOracle.actualChangeRate(), baseChangeRate);
        assertEq(systemOracle.rateModel(), address(rateModel));
        assertEq(systemOracle.TIMEFRAME(), TIMEFRAME);
    }

    function testOraclePriceGrowsOverPeriod() public {
        uint256 changeRate = systemOracle.actualChangeRate();

        // before periodStartTime, rate doesn't grow
        assertEq(systemOracle.getCurrentOraclePrice(), initialOraclePrice);
        vm.warp(periodStartTime / 2);
        assertEq(systemOracle.getCurrentOraclePrice(), initialOraclePrice);
        vm.warp(periodStartTime);
        assertEq(systemOracle.getCurrentOraclePrice(), initialOraclePrice);
        // after periodStartTime, rate grows linearly over the period of TIMEFRAME
        vm.warp(periodStartTime + TIMEFRAME / 2);
        assertEq(
            systemOracle.getCurrentOraclePrice(),
            initialOraclePrice + changeRate / 2
        );
        vm.warp(periodStartTime + TIMEFRAME);
        assertEq(
            systemOracle.getCurrentOraclePrice(),
            initialOraclePrice + changeRate
        );
        // the rate doesn't grow after period end (periodStartTime + TIMEFRAME)
        vm.warp(periodStartTime + TIMEFRAME * 2);
        assertEq(
            systemOracle.getCurrentOraclePrice(),
            initialOraclePrice + changeRate
        );
    }

    function testFuzzOraclePriceGrowsOverPeriod(
        uint256 currentTimestamp
    ) public {
        vm.assume(currentTimestamp <= TIMEFRAME * 2);
        vm.warp(currentTimestamp);

        uint256 changeRate = systemOracle.actualChangeRate();

        // before periodStartTime, rate doesn't grow
        if (currentTimestamp < periodStartTime) {
            assertEq(systemOracle.getCurrentOraclePrice(), initialOraclePrice);
        }
        // the rate doesn't grow after period end (periodStartTime + TIMEFRAME)
        else if (currentTimestamp > periodStartTime + TIMEFRAME) {
            assertEq(
                systemOracle.getCurrentOraclePrice(),
                initialOraclePrice + changeRate
            );
        }
        // after periodStartTime, rate grows linearly over the period of TIMEFRAME
        // use different lerp implementation to double-check business logic
        else {
            uint256 expectedAccruedYield = _lerp(
                currentTimestamp,
                periodStartTime,
                periodStartTime + TIMEFRAME,
                0,
                changeRate
            );
            assertEq(
                systemOracle.getCurrentOraclePrice(),
                initialOraclePrice + expectedAccruedYield
            );
        }
    }

    function testUpdateBaseRate() public {
        lastLiquidVenuePercentage = 0.5e18; // 50%, enough liquid reserves for 0 boost

        // grow at default change rate for half of TIMEFRAME
        vm.warp(periodStartTime + TIMEFRAME / 2);
        assertEq(systemOracle.baseChangeRate(), baseChangeRate);
        assertEq(systemOracle.actualChangeRate(), baseChangeRate); // 10% APR
        assertEq(
            systemOracle.getCurrentOraclePrice(),
            initialOraclePrice + baseChangeRate / 2
        ); // 1.05$
        assertEq(systemOracle.periodStartTime(), uint64(periodStartTime));
        assertEq(
            systemOracle.periodStartOraclePrice(),
            uint192(initialOraclePrice)
        );

        // set base rate to 3x the current base rate
        uint256 newBaseRate = baseChangeRate * 3; // 30% APR
        uint64 expectedNewPeriodStartTime = uint64(
            periodStartTime + TIMEFRAME / 2
        );
        uint192 expectedNewPeriodStartOraclePrice = uint192(1.05e18);
        // check events
        vm.expectEmit(false, false, false, true, address(systemOracle));
        emit InterestCompounded(
            expectedNewPeriodStartTime,
            expectedNewPeriodStartOraclePrice
        );
        vm.expectEmit(false, false, false, true, address(systemOracle));
        emit BaseRateUpdated(
            expectedNewPeriodStartTime,
            baseChangeRate,
            newBaseRate
        );
        vm.expectEmit(false, false, false, true, address(systemOracle));
        emit ActualRateUpdated(
            expectedNewPeriodStartTime,
            baseChangeRate,
            newBaseRate
        );
        // prank & update base rate
        vm.prank(addresses.governorAddress);
        systemOracle.updateBaseRate(newBaseRate);

        // check updated rates
        assertEq(systemOracle.baseChangeRate(), newBaseRate);
        assertEq(systemOracle.actualChangeRate(), newBaseRate);

        // should have started a new period
        assertEq(
            systemOracle.periodStartTime(),
            uint64(periodStartTime + TIMEFRAME / 2)
        );
        assertEq(
            systemOracle.periodStartOraclePrice(),
            expectedNewPeriodStartOraclePrice
        );
        assertEq(
            systemOracle.getCurrentOraclePrice(),
            systemOracle.periodStartOraclePrice()
        );

        // grow at new change rate for half of TIMEFRAME
        vm.warp(periodStartTime + TIMEFRAME);
        assertEq(systemOracle.getCurrentOraclePrice(), 1.2075e18);

        // still grow for half of TIMEFRAME because a new period has started
        vm.warp(periodStartTime + (TIMEFRAME * 3) / 2);
        assertEq(systemOracle.getCurrentOraclePrice(), 1.365e18);
    }

    function testUpdateBaseRateLowLiquidity() public {
        lastLiquidVenuePercentage = 0; // 0% => max boost
        uint256 maxRate = rateModel.MAXIMUM_CHANGE_RATE();

        vm.warp(periodStartTime);

        // set base rate to 3x the current base rate
        uint256 newBaseRate = baseChangeRate * 3;
        // check events
        vm.expectEmit(false, false, false, true, address(systemOracle));
        emit InterestCompounded(uint64(periodStartTime), 1e18);
        vm.expectEmit(false, false, false, true, address(systemOracle));
        emit BaseRateUpdated(
            uint64(periodStartTime),
            baseChangeRate,
            newBaseRate
        );
        vm.expectEmit(false, false, false, true, address(systemOracle));
        emit ActualRateUpdated(
            uint64(periodStartTime),
            baseChangeRate,
            maxRate
        );
        // prank & update base rate
        vm.prank(addresses.governorAddress);
        systemOracle.updateBaseRate(newBaseRate);

        // check updated rates
        assertEq(systemOracle.baseChangeRate(), newBaseRate);
        assertEq(systemOracle.actualChangeRate(), maxRate);
    }

    function testUpdateBaseRateAcl() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a governor"));
        systemOracle.updateBaseRate(0);
    }

    function testSetRateModel() public {
        uint256 currentTimestamp = periodStartTime;
        vm.warp(currentTimestamp);
        assertEq(systemOracle.rateModel(), address(rateModel));

        // check events
        vm.expectEmit(false, false, false, true, address(systemOracle));
        emit RateModelUpdated(currentTimestamp, address(rateModel), address(0));

        // prank & call
        vm.prank(addresses.governorAddress);
        systemOracle.setRateModel(address(0));
        assertEq(systemOracle.rateModel(), address(0));

        // check events
        vm.expectEmit(false, false, false, true, address(systemOracle));
        emit RateModelUpdated(currentTimestamp, address(0), address(rateModel));

        // prank & call
        vm.prank(addresses.governorAddress);
        systemOracle.setRateModel(address(rateModel));
        assertEq(systemOracle.rateModel(), address(rateModel));
    }

    function testSetRateModelAcl() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a governor"));
        systemOracle.setRateModel(address(0));
    }

    function testUpdateActualRateFuzz(
        uint256 baseRate,
        uint256 liquidReserves
    ) public {
        vm.assume(baseRate < 100e18); // never set a base rate > 1000% APR
        vm.assume(liquidReserves <= 1e18); // percent of liquid reserves can't be >100%

        // initialize state with the fuzzed base rate
        vm.warp(periodStartTime);
        vm.prank(addresses.governorAddress);
        systemOracle.updateBaseRate(baseRate);

        // trust DynamicVotlRateModel.getRate to get the actualRate,
        // see actual fuzz tests in DynamicVoltRateModel.t.sol for
        // checks on the correctness of this value.
        uint256 actualRate = rateModel.getRate(baseRate, liquidReserves);

        // check events
        vm.expectEmit(false, false, false, true, address(systemOracle));
        emit InterestCompounded(
            uint64(periodStartTime),
            uint192(initialOraclePrice)
        );
        vm.expectEmit(false, false, false, true, address(systemOracle));
        emit ActualRateUpdated(periodStartTime, baseRate, actualRate);
        systemOracle.updateActualRate(liquidReserves);

        // check state
        assertEq(systemOracle.periodStartTime(), uint64(periodStartTime));
        assertEq(
            systemOracle.periodStartOraclePrice(),
            uint192(initialOraclePrice)
        );
        assertEq(systemOracle.baseChangeRate(), baseRate);
        assertEq(systemOracle.actualChangeRate(), actualRate);
    }

    function testUpdateActualRateAcl() public {
        vm.prank(address(0));
        vm.expectRevert(bytes("MGO: Not PCV Oracle"));
        systemOracle.updateActualRate(1e18);
    }
}

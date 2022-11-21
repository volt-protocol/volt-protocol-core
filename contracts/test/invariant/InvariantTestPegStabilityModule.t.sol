// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "../unit/utils/Vm.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {ICoreV2} from "../../core/ICoreV2.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockMorpho} from "../../mock/MockMorpho.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {MockPCVOracle} from "../../mock/MockPCVOracle.sol";
import {DSInvariantTest} from "../unit/utils/DSInvariantTest.sol";
import {VoltSystemOracle} from "../../oracle/VoltSystemOracle.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {IGRLM, GlobalRateLimitedMinter} from "../../minter/GlobalRateLimitedMinter.sol";
import {getCoreV2, getAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";

/// note all variables have to be public and not immutable otherwise foundry
/// will not run invariant tests

/// @dev Modified from Solmate ERC20 Invariant Test (https://github.com/transmissions11/solmate/blob/main/src/test/ERC20.t.sol)
contract InvariantTestPegStabilityModule is DSTest, DSInvariantTest {
    using SafeCast for *;

    ICoreV2 public core;
    MockERC20 public token;
    MockMorpho public morpho;
    PegStabilityModule public psm;
    PCVGuardian public pcvGuardian;
    MockPCVOracle public pcvOracle;
    VoltSystemOracle private oracle;
    GlobalRateLimitedMinter public grlm;
    PegStabilityModuleTest public morphoTest;

    Vm private vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    /// ---------- PSM PARAMS ----------

    uint128 public constant voltFloorPrice = 1.05e6; /// 1 volt for 1.05 usdc is the min price
    uint128 public constant voltCeilingPrice = 1.1e6; /// 1 volt for 1.1 usdc is the max price

    /// ---------- GRLM PARAMS ----------

    /// maximum rate limit per second is 100 VOLT
    uint256 public constant maxRateLimitPerSecondMinting = 100e18;

    /// replenish 500k VOLT per day
    uint128 public constant rateLimitPerSecondMinting = 5.787e18;

    /// buffer cap of 1.5m VOLT
    uint128 public constant bufferCapMinting = 1_500_000e18;

    function setUp() public {
        pcvOracle = new MockPCVOracle();
        core = getCoreV2();
        token = new MockERC20();
        oracle = new VoltSystemOracle(0, block.timestamp, voltFloorPrice + 1);
        psm = new PegStabilityModule(
            address(core),
            address(oracle),
            address(0),
            0,
            false,
            IERC20(address(token)),
            voltFloorPrice,
            voltCeilingPrice
        );

        address[] memory toWhitelist = new address[](1);
        toWhitelist[0] = address(psm);

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this),
            toWhitelist
        );

        morphoTest = new PegStabilityModuleTest(
            psm,
            token,
            MockERC20(address(core.volt())),
            pcvGuardian
        );

        vm.prank(addresses.governorAddress);
        psm.setPCVOracle(address(pcvOracle));

        grlm = new GlobalRateLimitedMinter(
            address(core),
            maxRateLimitPerSecondMinting,
            rateLimitPerSecondMinting,
            bufferCapMinting
        );

        vm.startPrank(addresses.governorAddress);

        core.grantMinter(address(grlm));
        core.grantLocker(address(psm));
        core.grantLocker(address(grlm));
        core.grantLocker(address(pcvGuardian));

        core.grantRateLimitedMinter(address(psm));
        core.grantRateLimitedRedeemer(address(psm));
        core.grantPCVController(address(pcvGuardian));
        core.setGlobalRateLimitedMinter(IGRLM(address(grlm)));

        vm.stopPrank();

        addTargetContract(address(morphoTest));
    }

    function invariantLastRecordedBalance() public {
        assertEq(
            pcvOracle.pcvAmount().toUint256(),
            morphoTest.totalDeposited()
        );
        assertEq(pcvOracle.pcvAmount().toUint256(), psm.balance());
    }
}

contract PegStabilityModuleTest is DSTest {
    MockERC20 public volt;
    MockERC20 public token;
    uint256 public totalDeposited;
    PegStabilityModule public psm;
    PCVGuardian public pcvGuardian;

    Vm private vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    constructor(
        PegStabilityModule _psm,
        MockERC20 _token,
        MockERC20 _volt,
        PCVGuardian _pcvGuardian
    ) {
        psm = _psm;
        token = _token;
        volt = _volt;
        pcvGuardian = _pcvGuardian;
    }

    function mint(uint96 amount) public {
        token.mint(address(this), amount);
        token.approve(address(psm), amount);

        uint256 minAmountOut = psm.getMintAmountOut(amount);
        psm.mint(address(this), amount, minAmountOut);
        unchecked {
            /// unchecked because token, PSM or GlobalRateLimitedMinter
            /// will revert from an integer overflow
            totalDeposited += amount;
        }
    }

    function redeem(uint96 amount) public {
        volt.mint(address(this), amount);
        volt.approve(address(psm), amount);

        uint256 redeemAmountOut = psm.getRedeemAmountOut(amount);
        vm.prank(addresses.pcvControllerAddress);
        psm.redeem(address(this), amount, redeemAmountOut);
        unchecked {
            /// unchecked because amount is always less than or equal
            /// to totalDeposited
            totalDeposited -= redeemAmountOut;
        }
    }

    function withdraw(uint96 amount) public {
        vm.prank(addresses.pcvControllerAddress);
        pcvGuardian.withdrawToSafeAddress(address(psm), amount);
        unchecked {
            totalDeposited -= amount;
        }
    }
}

pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Decimal} from "../external/Decimal.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {PCVDeposit} from "../pcv/PCVDeposit.sol";
import {OracleRefV2} from "../refs/OracleRefV2.sol";
import {IPriceBoundPSMV2} from "./IPriceBoundPSMV2.sol";
import {IERC20BurnableMintable} from "./../utils/IERC20BurnableMintable.sol";
import {GlobalRateLimitedMinter} from "./../minter/GlobalRateLimitedMinter.sol";

contract PriceBoundPSMV2 is IPriceBoundPSMV2, OracleRefV2 {
    using Decimal for Decimal.D256;
    using SafeERC20 for IERC20;

    /// @notice reference to underlying token
    IERC20 public immutable underlyingToken;

    /// @notice reference to the global pcv deposit
    address public immutable pcvDeposit;

    /// @notice reference to the global rate limited minter
    GlobalRateLimitedMinter public immutable grlm;

    /// @notice minimum floor price from the oracle
    uint256 public immutable floorPrice;

    /// @notice maximum ceiling price from the oracle
    uint256 public immutable ceilingPrice;

    /// @notice
    /// @param _core reference to the core smart contract
    /// @param _pcvDeposit reference to the single pcv deposit smart contract
    /// @param _underlyingToken reference to the underlying token this psm exchanges with
    /// @param _grlm reference to the global rate limited minter smart contract
    /// @param _floorPrice minimum acceptable oracle price
    /// @param _ceilingPrice maximum acceptable oracle price
    constructor(
        address _core,
        address _pcvDeposit,
        address _underlyingToken,
        address _grlm,
        uint256 _floorPrice,
        uint256 _ceilingPrice,
        address _oracle,
        address _backupOracle,
        int256 _decimalsNormalizer
    ) OracleRefV2(_core, _oracle, _backupOracle, _decimalsNormalizer, false) {
        pcvDeposit = _pcvDeposit;
        underlyingToken = IERC20(_underlyingToken);
        grlm = GlobalRateLimitedMinter(_grlm);
        floorPrice = _floorPrice;
        ceilingPrice = _ceilingPrice;
    }

    /// @notice get volt
    /// @param to address that receives the Volt
    /// @param amountAssetIn amount of underlying token to transfer in
    /// @param minAmountVoltOut minimum amount of Volt received for transaction to succeed
    function mint(
        address to,
        uint256 amountAssetIn,
        uint256 minAmountVoltOut
    ) external globalReentrancyLock returns (uint256 amountVoltOut) {
        amountVoltOut = getMintAmountOut(amountAssetIn);
        require(amountVoltOut >= minAmountVoltOut, "PSM: not enough Volt out");

        underlyingToken.safeTransferFrom(msg.sender, pcvDeposit, amountAssetIn);
        grlm.mintVolt(to, amountVoltOut);

        emit Mint(to, amountAssetIn, amountVoltOut);
    }

    /// @notice dispose of volt
    /// @param to address that receives the Volt
    /// @param amountVoltIn amount of volt to burn
    /// @param minAmountUnderlyingOut minimum amount of underlying received for transaction to succeed
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountUnderlyingOut
    ) external globalReentrancyLock returns (uint256 amountUnderlyingOut) {
        amountUnderlyingOut = getRedeemAmountOut(amountVoltIn);
        require(
            amountUnderlyingOut >= minAmountUnderlyingOut,
            "PSM: not enough underlying out"
        );

        /// burn Volt
        IERC20BurnableMintable(address(volt())).burnFrom(
            msg.sender,
            amountVoltIn
        );

        /// update global rate limit to allow additional minting
        grlm.replenishBuffer(amountVoltIn);

        /// send underlying token to recipient
        PCVDeposit(pcvDeposit).withdrawERC20(
            address(underlyingToken),
            to,
            amountUnderlyingOut
        );

        emit Redeem(to, amountVoltIn, amountUnderlyingOut);
    }

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    /// First get oracle price of token
    /// Then figure out how many dollars that amount in is worth by multiplying price * amount.
    /// ensure decimals are normalized if on underlying they are not 18
    function getMintAmountOut(uint256 amountAssetIn)
        public
        view
        returns (uint256 amountVoltOut)
    {
        Decimal.D256 memory oraclePrice = readOracle();
        _validatePriceRange(oraclePrice);

        // This was included to make sure that precision is retained when dividing
        // In the case where 1 USDC is deposited, which is 1e6, at the time of writing
        // the VOLT price is $1.05 so the price we retrieve from the oracle will be 1.05e6
        // VOLT contains 18 decimals, so when we perform the below calculation, it amounts to
        // 1e16 * 1e18 / 1.05e6 = 1e24 / 1.05e6 which lands us at around 0.95e17, which is 0.95
        // VOLT for 1 USDC which is consistent with the exchange rate
        amountVoltOut = (amountAssetIn * 1e18) / oraclePrice.value;
    }

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
    /// First get oracle price of token
    /// Then figure out how many dollars that amount in is worth by multiplying price * amount.
    /// ensure decimals are normalized if on underlying they are not 18
    function getRedeemAmountOut(uint256 amountVoltIn)
        public
        view
        returns (uint256 amountTokenOut)
    {
        Decimal.D256 memory oraclePrice = readOracle();
        _validatePriceRange(oraclePrice);

        amountTokenOut = oraclePrice.mul(amountVoltIn).asUint256();
    }

    /// @notice return whether the current price is valid
    function isPriceValid() public view returns (bool) {
        Decimal.D256 memory oraclePrice = readOracle();

        return _validPrice(oraclePrice);
    }

    /// @notice helper function to determine if price is within a valid range
    function _validPrice(Decimal.D256 memory price)
        internal
        view
        returns (bool valid)
    {
        valid = price.value >= floorPrice && price.value <= ceilingPrice;
    }

    /// @notice reverts if the price is greater than or equal to the ceiling
    /// or less than or equal to the floor
    function _validatePriceRange(Decimal.D256 memory price) internal view {
        require(_validPrice(price), "PegStabilityModule: price out of bounds");
    }
}

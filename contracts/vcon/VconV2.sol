// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC20Gauges} from "./tribedao-flywheel-v2/ERC20Gauges.sol";
import {ERC20MultiVotes} from "./tribedao-flywheel-v2/ERC20MultiVotes.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {ERC20Lockable} from "./ERC20Lockable.sol";
import {IMarketGovernanceRewards} from "./IMarketGovernanceRewards.sol";

contract VconV2 is
    CoreRefV2,
    ERC20,
    ERC20Lockable,
    ERC20Gauges,
    ERC20MultiVotes
{
    /// @notice on release, VCON transfers are disabled.
    /// Governance can enable them at a later date.
    bool public transfersEnabled;
    address public marketGovernanceRewards;

    constructor(
        address _core
    )
        CoreRefV2(_core)
        ERC20Gauges(7 days, 1 days)
        ERC20("Volt Controller", "VCON", 18)
    {}

    ////////////////////////////////////////////////////////////////
    //  VCON Administration functions
    ////////////////////////////////////////////////////////////////

    /// @notice Enable transfers, that are disabled by default.
    /// Once enabled, governance cannot disable transfers.
    function enableTransfers() external onlyGovernor {
        transfersEnabled = true;
    }

    /// @notice Set the market governance rewards contract.
    /// If this is set to a non-zero address, all ERC20 transfer() and
    /// transferFrom() will be blocked for users that do not have 0
    /// gauge weights.
    /// The marketGovernanceRewards address will be notified of gauge weight
    /// changes when users change their desired allocations.
    function setMarketGovernanceRewards(
        address _marketGovernanceRewards
    ) external onlyGovernor {
        // TODO: think about everything that needs update when we set a new
        // address for this. Not sure it's really possible to change on the fly.
        marketGovernanceRewards = _marketGovernanceRewards;
    }

    ////////////////////////////////////////////////////////////////
    //  VCON Overrides to notify MarketGovernanceRewards
    ////////////////////////////////////////////////////////////////

    function incrementGauge(
        address gauge,
        uint112 weight
    ) external returns (uint112 newUserWeight) {
        // Default behavior
        newUserWeight = _incrementGauge(gauge, weight);

        address _marketGovernanceRewards = marketGovernanceRewards; // sload
        if (_marketGovernanceRewards != address(0)) {
            // If set, notify MarketGovernanceRewards of weight change
            Weight storage gaugeWeight = _getGaugeWeight[gauge]; // sload
            IMarketGovernanceRewards(_marketGovernanceRewards)
                .userGaugeWeightChanged( // call
                msg.sender,
                gauge,
                gaugeWeight.currentCycle,
                gaugeWeight.currentWeight,
                newUserWeight
            );

            // If set, and it's the first user gauge weight change,
            // then lock the user's tokens on MarketGovernanceRewards.
            if (newUserWeight != 0 && lockAddress[msg.sender] == address(0)) {
                _setLockAddress(msg.sender, _marketGovernanceRewards);
            }
        }
    }

    function incrementGauges(
        address[] calldata gaugeList,
        uint112[] calldata weights
    ) external returns (uint112 newUserWeight) {
        // Default behavior
        newUserWeight = _incrementGauges(gaugeList, weights);

        address _marketGovernanceRewards = marketGovernanceRewards; // sload
        if (_marketGovernanceRewards != address(0)) {
            // If set, notify MarketGovernanceRewards of weight change
            for (uint256 i = 0; i < gaugeList.length; ) {
                address gauge = gaugeList[i];
                Weight storage gaugeWeight = _getGaugeWeight[gauge]; // sload
                IMarketGovernanceRewards(_marketGovernanceRewards)
                    .userGaugeWeightChanged( // call
                    msg.sender,
                    gauge,
                    gaugeWeight.currentCycle,
                    gaugeWeight.currentWeight,
                    newUserWeight
                );
                unchecked {
                    i++;
                }
            }

            // If set, and it's the first user gauge weight change,
            // then lock the user's tokens on MarketGovernanceRewards.
            if (newUserWeight != 0 && lockAddress[msg.sender] == address(0)) {
                _setLockAddress(msg.sender, _marketGovernanceRewards);
            }
        }
    }

    function decrementGauge(
        address gauge,
        uint112 weight
    ) external returns (uint112 newUserWeight) {
        // Default behavior
        newUserWeight = _decrementGauge(gauge, weight);

        address _marketGovernanceRewards = marketGovernanceRewards; // sload
        if (_marketGovernanceRewards != address(0)) {
            // If set, notify MarketGovernanceRewards of weight change
            Weight storage gaugeWeight = _getGaugeWeight[gauge]; // sload
            IMarketGovernanceRewards(_marketGovernanceRewards)
                .userGaugeWeightChanged( // call
                msg.sender,
                gauge,
                gaugeWeight.currentCycle,
                gaugeWeight.currentWeight,
                newUserWeight
            );
        }
    }

    function decrementGauges(
        address[] calldata gaugeList,
        uint112[] calldata weights
    ) external returns (uint112 newUserWeight) {
        // Default behavior
        newUserWeight = _decrementGauges(gaugeList, weights);

        address _marketGovernanceRewards = marketGovernanceRewards; // sload
        if (_marketGovernanceRewards != address(0)) {
            // If set, notify MarketGovernanceRewards of weight change
            for (uint256 i = 0; i < gaugeList.length; ) {
                address gauge = gaugeList[i];
                Weight storage gaugeWeight = _getGaugeWeight[gauge]; // sload
                IMarketGovernanceRewards(_marketGovernanceRewards)
                    .userGaugeWeightChanged( // call
                    msg.sender,
                    gauge,
                    gaugeWeight.currentCycle,
                    gaugeWeight.currentWeight,
                    newUserWeight
                );
                unchecked {
                    i++;
                }
            }
        }
    }

    ////////////////////////////////////////////////////////////////
    //  ERC20 Mint & Burn
    ////////////////////////////////////////////////////////////////

    function mint(
        address to,
        uint256 amount
    ) external onlyVoltRole(VoltRoles.VCON_MINTER) {
        _mint(to, amount);
    }

    function burn(
        address from,
        uint256 amount
    ) external onlyVoltRole(VoltRoles.VCON_BURNER) {
        _burn(from, amount);
    }

    ////////////////////////////////////////////////////////////////
    //  ERC20 LOGIC to merge implementations
    ////////////////////////////////////////////////////////////////

    function _burn(
        address from,
        uint256 amount
    )
        internal
        virtual
        override(ERC20, ERC20Lockable, ERC20Gauges, ERC20MultiVotes)
    {
        _checkLockedTransfer(from, address(0));
        _decrementWeightUntilFree(from, amount);
        _decrementVotesUntilFree(from, amount);
        ERC20._burn(from, amount);
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual override(ERC20, ERC20Lockable) returns (bool) {
        return ERC20Lockable.approve(spender, amount);
    }

    function transfer(
        address to,
        uint256 amount
    )
        public
        virtual
        override(ERC20, ERC20Lockable, ERC20Gauges, ERC20MultiVotes)
        returns (bool)
    {
        require(transfersEnabled, "VconV2: transfers not yet enabled");
        _checkLockedTransfer(msg.sender, to);
        /// @dev if market governance rewards are enabled, user must have no active
        /// gauge votings (choices on where to direct PCV) to perform outbound transfers.
        if (marketGovernanceRewards != address(0)) {
            require(
                getUserWeight[msg.sender] == 0,
                "VconV2: gauge weights must be 0 to transfer"
            );
        } else {
            _decrementWeightUntilFree(msg.sender, amount);
        }
        _decrementVotesUntilFree(msg.sender, amount);
        return ERC20.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    )
        public
        virtual
        override(ERC20, ERC20Lockable, ERC20Gauges, ERC20MultiVotes)
        returns (bool)
    {
        require(transfersEnabled, "VconV2: transfers not yet enabled");
        _checkLockedTransfer(from, to);
        /// @dev if market governance rewards are enabled, user must have no active
        /// gauge votings (choices on where to direct PCV) to perform outbound transfers.
        if (marketGovernanceRewards != address(0)) {
            require(
                getUserWeight[from] == 0,
                "VconV2: gauge weights must be 0 to transferFrom"
            );
        } else {
            _decrementWeightUntilFree(from, amount);
        }
        _decrementVotesUntilFree(from, amount);
        return ERC20.transferFrom(from, to, amount);
    }

    ////////////////////////////////////////////////////////////////
    //  ERC20MultiVotes public functions with access control
    ////////////////////////////////////////////////////////////////

    function setMaxDelegates(uint256 newMax) external onlyGovernor {
        _setMaxDelegates(newMax);
    }

    function setContractExceedMaxDelegates(
        address account,
        bool canExceedMax
    ) external onlyGovernor {
        _setContractExceedMaxDelegates(account, canExceedMax);
    }

    ////////////////////////////////////////////////////////////////
    //  ERC20Gauges public functions with access control
    ////////////////////////////////////////////////////////////////

    function addGauge(
        address gauge
    ) external onlyVoltRole(VoltRoles.VCON_GAUGE_MANAGER) returns (uint112) {
        return _addGauge(gauge);
    }

    function removeGauge(
        address gauge
    ) external onlyVoltRole(VoltRoles.VCON_GAUGE_MANAGER) {
        _removeGauge(gauge);
    }

    function replaceGauge(
        address oldGauge,
        address newGauge
    ) external onlyVoltRole(VoltRoles.VCON_GAUGE_MANAGER) {
        _removeGauge(oldGauge);
        _addGauge(newGauge);
    }

    function setMaxGauges(
        uint256 newMax
    ) external onlyVoltRole(VoltRoles.VCON_GAUGE_MANAGER) {
        _setMaxGauges(newMax);
    }

    function setContractExceedMaxGauges(
        address account,
        bool canExceedMax
    ) external onlyVoltRole(VoltRoles.VCON_GAUGE_MANAGER) {
        _setContractExceedMaxGauges(account, canExceedMax);
    }
}

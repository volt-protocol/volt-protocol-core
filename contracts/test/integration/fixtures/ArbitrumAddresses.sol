// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

library ArbitrumAddresses {
    // ---------- VOLT ADDRESSES ----------
    address public constant CORE = 0x31A38B79fDcFBC3095E3268CAFac1b9791796736;
    address public constant VOLT = 0x6Ba6f18a290Cd55cf1B00be2bEc5c954cb29fAc5;

    /// ---------- CURRENT ORACLES ----------
    address public constant ORACLE_PASS_THROUGH =
        0xcd836280e4416e08F54E5584Bcd49Ac2E3a68747;
    address public constant VOLT_SYSTEM_ORACLE_0_BIPS =
        0xACce8F8661f7f214b94f94e3e1A09d81f0B924D6;

    /// deprecated oracles
    address public constant VOLT_SYSTEM_ORACLE =
        0x69DBf8dD98Aa40F50E4f2263c6f2d66f26f9cb5b;
    address public constant VOLT_SYSTEM_ORACLE_144_BIPS =
        0x5DDf983CbD5819c13661046110EfCd2E8629d40b;
    address public constant DEPRECATED_ORACLE_PASS_THROUGH =
        0x7A23eB9bf043471dE7422a9CcdB5Ef809F34CbdE;
    address public constant DEPRECATED_SCALING_PRICE_ORACLE =
        0x138F30D35557FA72478663b601f0f0FD7cc4E39E;

    /// @notice ERC20ALLOCATOR
    address public constant ERC20ALLOCATOR =
        0x37518BbE48fEaE49ECBD83F7e9C01c1A6b4c2F69; // update with actual address once deployed

    /// @notice multisig governor
    address public constant GOVERNOR =
        0x1A1075cef632624153176CCf19Ae0175953CF010;
    /// @notice PCV Guardian smart contract
    address public constant PCV_GUARDIAN =
        0x14eCB5Ff2A78364E0FF443B7F0F6e0e393531484;
    /// @notice deployer
    address public constant DEPLOYER =
        0x25dCffa22EEDbF0A69F6277e24C459108c186ecB;

    /// @notice timelock under active use
    address public constant TIMELOCK_CONTROLLER =
        0x2c01C9166FA3e16c24c118053E346B1DD8e72dE8;

    /// current active EOA's
    address public constant EOA_1 = 0xB320e376Be6459421695F2b6B1E716AE4bc8129A;
    address public constant EOA_2 = 0xd90E9181B20D8D1B5034d9f5737804Da182039F6;
    address public constant EOA_3 = 0xA96D4a5c343d6fE141751399Fc230E9E8Ecb6fb6;

    /// inactive EOA's
    address public constant REVOKED_EOA_1 =
        0xf8D0387538E8e03F3B4394dA89f221D7565a28Ee;

    address public constant DEPRECATED_TIMELOCK =
        0x980A05105a53eCa7745DA40DF1AdE6674fc73eD5;

    address public constant VOLT_DAI_PSM =
        0x4d2cF840FDe4210A96F485fC01f1459Bfb2EFABb;

    address public constant VOLT_USDC_PSM =
        0x278A903dA9Fb0ea8B90c2b1b089eF90033FDd868;

    address public constant PCV_GUARD_ADMIN =
        0x0d6d0600BEa83FaAF172C2E8aCDd2F5140e235D3;

    // ---------- TOKEN ADDRESSES ----------

    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    address public constant DAI_MINTER_1 =
        0x10E6593CDda8c58a1d0f14C5164B376352a55f2F;
    address public constant DAI_MINTER_2 =
        0x467194771dAe2967Aef3ECbEDD3Bf9a310C76C65;

    address public constant USDC_WHALE =
        0x489ee077994B6658eAfA855C308275EAd8097C4A;

    // ---------- CHAINLINK ADDRESSES ----------

    address public constant CHAINLINK_ORACLE_ADDRESS =
        0xf76F586F6aAC0c8dE147Eea75D76AB7c2f23eDC2;
}

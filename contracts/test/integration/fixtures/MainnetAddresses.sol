// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

library MainnetAddresses {
    // ---------- VOLT ADDRESSES ----------
    address public constant CORE = 0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196;
    address public constant VOLT = 0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18;
    address public constant ORACLE_PASS_THROUGH =
        0x84dc71500D504163A87756dB6368CC8bB654592f;
    address public constant GOVERNOR =
        0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf;
    address public constant PCV_GUARDIAN =
        0x2c2b362e6ae0F080F39b90Cb5657E5550090D6C3;
    address public constant DEPLOYER =
        0x25dCffa22EEDbF0A69F6277e24C459108c186ecB;

    address public constant VOLT_FEI_PSM =
        0x985f9C331a9E4447C782B98D6693F5c7dF8e560e;

    address public constant TIMELOCK_CONTROLLER =
        0x75d078248eE49c585b73E73ab08bb3eaF93383Ae;

    /// current active EOA's
    address public constant EOA_1 = 0xB320e376Be6459421695F2b6B1E716AE4bc8129A;
    address public constant EOA_2 = 0xd90E9181B20D8D1B5034d9f5737804Da182039F6;
    address public constant EOA_3 = 0xA96D4a5c343d6fE141751399Fc230E9E8Ecb6fb6;

    /// inactive EOA's
    address public constant REVOKED_EOA_1 =
        0xf8D0387538E8e03F3B4394dA89f221D7565a28Ee;

    address public constant NC_PSM = 0x18f251FC3CE0Cb690F13f62213aba343657d0E72;
    address public constant GRLM = 0x87945f59E008aDc9ed6210a8e061f009d6ace718;
    address public constant PCV_GUARD_ADMIN =
        0x868F58Ae8F6B2Dc31D9ADc97a8A09B16f05E9cd7;

    // ---------- FEI ADDRESSES ----------

    address public constant FEI_CORE =
        0x8d5ED43dCa8C2F7dFB20CF7b53CC7E593635d7b9;

    address public constant FEI_DAO_TIMELOCK =
        0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c;

    address public constant FEI_GOVERNOR =
        0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c;

    // ---------- USDC ADDRESSES ----------

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address public constant MAKER_USDC_PSM =
        0xAe2D4617c862309A3d75A0fFB358c7a5009c673F;
    address public constant FEI = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;

    // ---------- CHAINLINK ADDRESSES ----------

    address public constant CHAINLINK_ORACLE_ADDRESS =
        0x049Bd8C3adC3fE7d3Fc2a44541d955A537c2A484;

    // ---------- PCV DEPOSIT ADDRESSES ----------

    address public constant RARI_VOLT_PCV_DEPOSIT =
        0xFeBDf448C8484834bb399d930d7E1bdC773E23bA;
}

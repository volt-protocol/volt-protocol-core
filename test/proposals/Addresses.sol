// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {Test} from "@forge-std/Test.sol";

contract Addresses is Test {
    mapping(string => address) private _mainnet;

    struct RecordedAddress {
        string name;
        address addr;
    }
    RecordedAddress[] private recordedAddresses;

    constructor() {
        // ---------- VOLT ADDRESSES ----------
        _addMainnet("V1_CORE", 0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196);
        _addMainnet("CORE", 0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196);
        _addMainnet(
            "ERC20ALLOCATOR",
            0x37518BbE48fEaE49ECBD83F7e9C01c1A6b4c2F69
        );
        _addMainnet("GOVERNOR", 0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf);
        _addMainnet("PCV_GUARDIAN", 0x2c2b362e6ae0F080F39b90Cb5657E5550090D6C3);
        _addMainnet("DEPLOYER", 0x25dCffa22EEDbF0A69F6277e24C459108c186ecB);
        _addMainnet(
            "VOLT_TIMELOCK",
            0x860fa85f04f9d35B3471D8F7F7fA3Ad31Ce4D5Ae
        );
        _addMainnet("VOLT_FEI_PSM", 0x985f9C331a9E4447C782B98D6693F5c7dF8e560e);
        _addMainnet(
            "TIMELOCK_CONTROLLER",
            0x75d078248eE49c585b73E73ab08bb3eaF93383Ae
        );

        // ---------- LIVE PSM ADDRESSES ----------
        _addMainnet("VOLT_DAI_PSM", 0x42ea9cC945fca2dfFd0beBb7e9B3022f134d9Bdd);
        _addMainnet(
            "VOLT_USDC_PSM",
            0x0b9A7EA2FCA868C93640Dd77cF44df335095F501
        );
        _addMainnet("PSM_USDC", 0x0b9A7EA2FCA868C93640Dd77cF44df335095F501);

        /// contracts that are routers and interact with maker routers
        _addMainnet("MAKER_ROUTER", 0xC403da9AaC46d3AdcD1a1bBe774601C0ddc542F7);
        _addMainnet(
            "COMPOUND_PCV_ROUTER",
            0x6338Ec144279b1f05AF8C90216d90C5b54Fa4D8F
        );

        // ---------- MORPHO ADDRESSES ----------
        _addMainnet(
            "MORPHO_COMPOUND_PCV_ROUTER",
            0x579C400eaCA4b1D84956E7bD284d97611f78BA4E
        );
        _addMainnet(
            "MORPHO_COMPOUND_DAI_PCV_DEPOSIT",
            0x7aB2f4A29048392EfE0B57FD17a3BedBcD0891DC
        );
        _addMainnet(
            "MORPHO_COMPOUND_USDC_PCV_DEPOSIT",
            0xF10d810De7F0Fbd455De30f8c43AbA56F253B73B
        );

        // ---------- EULER ADDRESSES ----------
        _addMainnet("EULER_MAIN", 0x27182842E098f60e3D576794A5bFFb0777E025d3);
        _addMainnet("EULER_USDC", 0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716);
        _addMainnet("EULER_DAI", 0xe025E3ca2bE02316033184551D4d3Aa22024D9DC);

        // ---------- ORACLE ADDRESSES ----------
        _addMainnet(
            "ORACLE_PASS_THROUGH",
            0xe733985a92Bfd5BC676095561BacE90E04606E4a
        );
        _addMainnet(
            "VOLT_SYSTEM_ORACLE_144_BIPS",
            0xB8Ac4931A618B06498966cba3a560B867D8f567F
        );

        // ---------- ACTIVE EOA ADDRESSES ----------
        _addMainnet("EOA_1", 0xB320e376Be6459421695F2b6B1E716AE4bc8129A);
        _addMainnet("EOA_2", 0xd90E9181B20D8D1B5034d9f5737804Da182039F6);
        _addMainnet("EOA_4", 0x6ef71cA9cD708883E129559F5edBFb9d9D5C6148);

        _addMainnet(
            "PCV_GUARD_ADMIN",
            0x868F58Ae8F6B2Dc31D9ADc97a8A09B16f05E9cd7
        );

        // ---------- FEI ADDRESSES ----------
        _addMainnet("FEI_CORE", 0x8d5ED43dCa8C2F7dFB20CF7b53CC7E593635d7b9);
        _addMainnet(
            "FEI_DAO_TIMELOCK",
            0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c
        );
        _addMainnet(
            "FEI_TC_TIMELOCK",
            0xe0C7DE94395B629860Cbb3c42995F300F56e6d7a
        );
        _addMainnet("FEI_GOVERNOR", 0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c);
        _addMainnet(
            "FEI_PCV_GUARDIAN",
            0x02435948F84d7465FB71dE45ABa6098Fc6eC2993
        );
        _addMainnet("FEI_DAI_PSM", 0x2A188F9EB761F70ECEa083bA6c2A40145078dfc2);
        _addMainnet(
            "FINAL_FEI_DAI_PSM",
            0x7842186CDd11270C4Af8C0A99A5E0589c7F249ce
        );

        // ---------- TOKEN ADDRESSES ----------
        _addMainnet("V1_VOLT", 0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);
        _addMainnet("VOLT", 0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);
        _addMainnet("USDC", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        _addMainnet("FEI", 0x956F47F50A910163D8BF957Cf5846D573E7f87CA);
        _addMainnet("DAI", 0x6B175474E89094C44Da98b954EedeAC495271d0F);

        // ---------- ADDRESSES TO IMPERSONATE ----------
        _addMainnet(
            "KRAKEN_USDC_WHALE",
            0xAe2D4617c862309A3d75A0fFB358c7a5009c673F
        );

        // ---------- Compound ADDRESSES ----------
        _addMainnet("CDAI", 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        _addMainnet("CFEI", 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67);
        _addMainnet("CUSDC", 0x39AA39c021dfbaE8faC545936693aC917d5E7563);
        _addMainnet("COMP", 0xc00e94Cb662C3520282E6f5717214004A7f26888);
        _addMainnet(
            "COMPTROLLER_V2",
            0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
        );

        // ---------- Aave ADDRESSES ----------
        _addMainnet("ADAI", 0x028171bCA77440897B824Ca71D1c56caC55b68A3);
        _addMainnet("AUSDC", 0xBcca60bB61934080951369a648Fb03DF4F96263C);

        // ---------- Maker ADDRESSES ----------
        _addMainnet(
            "MAKER_DAI_USDC_PSM",
            0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A
        );
        _addMainnet("GEM_JOIN", 0x0A59649758aa4d66E25f08Dd01271e891fe52199);

        // ---------- PCV DEPOSIT ADDRESSES ----------
        _addMainnet(
            "COMPOUND_DAI_PCV_DEPOSIT",
            0xE3cbfd618463B7198fa0743AbFA56170557cc880
        );
        _addMainnet(
            "COMPOUND_FEI_PCV_DEPOSIT",
            0x604556Bbc4aB70B3c73d7bb6c4867B6239511301
        );
        _addMainnet(
            "COMPOUND_USDC_PCV_DEPOSIT",
            0x3B69e3073cf86099a9bbB650e8682D6FdCfb29db
        );

        // ---------- CURVE ADDRESSES ----------
        _addMainnet(
            "DAI_USDC_USDT_CURVE_POOL",
            0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7
        );

        // ---------- DEPRECATED ADDRESSES ----------
        _addMainnet(
            "REVOKED_EOA_1",
            0xf8D0387538E8e03F3B4394dA89f221D7565a28Ee
        );
        _addMainnet(
            "REVOKED_EOA_3",
            0xA96D4a5c343d6fE141751399Fc230E9E8Ecb6fb6
        );
        _addMainnet(
            "DEPRECATED_ORACLE_PASS_THROUGH",
            0x84dc71500D504163A87756dB6368CC8bB654592f
        );
        _addMainnet(
            "DEPRECATED_SCALING_PRICE_ORACLE",
            0x79412660E95F94a4D2d02a050CEA776200939917
        );
        _addMainnet(
            "VOLT_SYSTEM_ORACLE",
            0xD4546B5B7D28aE0E048c073DCD92358721CEA8D4
        );
        _addMainnet("VOLT_DEPOSIT", 0xBDC01c9743989429df9a4Fe24c908D87e462AbC1);
        _addMainnet("NC_PSM", 0x18f251FC3CE0Cb690F13f62213aba343657d0E72);
        _addMainnet("GRLM", 0x87945f59E008aDc9ed6210a8e061f009d6ace718);
        _addMainnet(
            "OTC_LOAN_REPAYMENT",
            0x590eb1a809377f786a11fa1968eF8c15eB44A12F
        );
        _addMainnet(
            "GLOBAL_RATE_LIMITED_MINTER",
            0x87945f59E008aDc9ed6210a8e061f009d6ace718
        );

        // ---------- MORPHO ADDRESSES ----------

        _addMainnet(
            "MORPHO_COMPOUND",
            0x8888882f8f843896699869179fB6E4f7e3B58888
        );
        _addMainnet(
            "MORPHO_LENS_COMPOUND",
            0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67
        );

        _addMainnet("MORPHO_AAVE", 0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);
        _addMainnet(
            "MORPHO_LENS_AAVE",
            0x507fA343d0A90786d86C7cd885f5C49263A91FF4
        );
    }

    function _addMainnet(string memory name, address addr) private {
        _mainnet[name] = addr;
        vm.label(addr, name);
    }

    function mainnet(string memory name) public view returns (address) {
        return _mainnet[name];
    }

    function addMainnet(string memory name, address addr) public {
        _addMainnet(name, addr);

        recordedAddresses.push(RecordedAddress({name: name, addr: addr}));
    }

    function resetRecordingAddresses() external {
        delete recordedAddresses;
    }

    function getRecordedAddresses()
        external
        view
        returns (string[] memory names, address[] memory addresses)
    {
        names = new string[](recordedAddresses.length);
        addresses = new address[](recordedAddresses.length);
        for (uint256 i = 0; i < recordedAddresses.length; i++) {
            names[i] = recordedAddresses[i].name;
            addresses[i] = recordedAddresses[i].addr;
        }
    }
}

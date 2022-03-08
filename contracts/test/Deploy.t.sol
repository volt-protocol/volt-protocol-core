pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVolt} from "../volt/Volt.sol";
import {Volt} from "../volt/Volt.sol";
import {ICore} from "../core/ICore.sol";
import {Core} from "../core/Core.sol";
import {Vm} from "./utils/Vm.sol";
import {DSTest} from "./utils/DSTest.sol";
import {getAddresses, FeiTestAddresses} from "./utils/Fixtures.sol";
import {CoreDeploy, Vcon} from "../core/CoreDeploy.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import "hardhat/console.sol";

contract DeployTest is DSTest {
    CoreDeploy private deploy;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    FeiTestAddresses public addresses = getAddresses();

    function setUp() public {
      deploy = new CoreDeploy();
    }

    function testDeployed() public {
      address futureVOLTAddress = deploy.getFutureVOLTAddress();
      address futureVCONAddress = deploy.getFutureVCONAddress();

      console.log("0000");
      Core core = deploy.deploy();
      Volt volt = Volt(address(core.volt()));
      Vcon vcon = Vcon(address(core.volt()));
      console.log("0001");

      assertEq(address(core.volt()), futureVOLTAddress);
      console.log("0002");
      assertEq(address(core.vcon()), futureVCONAddress);
      console.log("0003");
      console.log("volt: ", address(volt));
      console.log("is volt a contract: ", Address.isContract(address(core)));
      console.log("is core a contract: ", Address.isContract(address(volt)));

      assertEq(address(volt.core()), address(core));
      console.log("00");
      assertEq(vcon.minter(), address(this));
      console.log("01");

      assertTrue(Address.isContract(address(volt)));
      assertTrue(Address.isContract(address(vcon)));

      console.log("0");
      volt.totalSupply();
      console.log("1");
      vcon.totalSupply();
      console.log("2");

      assertEq(address(core.volt()), address(volt));
      assertEq(address(core.vcon()), address(vcon));

      assertEq(futureVOLTAddress, address(volt));
      assertEq(futureVCONAddress, address(vcon));

        // bytes32 voltHash;
        // bytes32 vconHash;

        // assembly {
        //   voltHash := extcodehash(futureVOLTAddress)
        //   vconHash := extcodehash(futureVCONAddress)
        // }
        // // assertTrue(Address.isContract(futureVCONAddress));

        // emit log_bytes32(voltHash);
        // emit log_bytes32(vconHash);
    }

    function testLogBytecodehash() public {
      address futureVOLTAddress = deploy.getFutureVOLTAddress();
      address futureVCONAddress = deploy.getFutureVCONAddress();

      Core core = deploy.deploy();
      Volt volt = Volt(address(core.volt()));
      Vcon vcon = Vcon(address(core.volt()));

      assertEq(address(core.volt()), futureVOLTAddress);
      assertEq(address(core.vcon()), futureVCONAddress);
      assertEq(address(volt.core()), address(core));
      assertEq(vcon.minter(), address(this));

      assertTrue(Address.isContract(address(volt)));
      assertTrue(Address.isContract(address(vcon)));

      volt.totalSupply();
      vcon.totalSupply();

        bytes32 voltHash;
        bytes32 vconHash;

        assembly {
          voltHash := extcodehash(futureVOLTAddress)
          vconHash := extcodehash(futureVCONAddress)
        }
        assertTrue(Address.isContract(futureVOLTAddress));
        assertTrue(Address.isContract(futureVCONAddress));

        emit log_bytes32(voltHash);
        emit log_bytes32(vconHash);
    }
}

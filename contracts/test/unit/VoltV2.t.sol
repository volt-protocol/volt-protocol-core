//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {VoltV2} from "../../volt/VoltV2.sol";
import {Core} from "../../core/Core.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./utils/Fixtures.sol";
import {ICore} from "../../core/ICore.sol";
import {stdError} from "../unit/utils/StdLib.sol";

contract UnitTestVoltV2 is DSTest {
    using SafeCast for *;
    VoltV2 private volt;
    ICore private core;
    VoltTestAddresses public addresses = getAddresses();

    Vm private vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        core = getCore();
        volt = new VoltV2();
    }

    function testTokenDetails() public {
        assertEq(volt.name(), "Volt");
        assertEq(volt.symbol(), "VOLT");
        assertEq(volt.decimals(), 18);
        assertEq(volt.totalSupply(), 0);
    }

    function testDelegate() public {
        volt.delegate(address(0xFFF));
        assertEq(volt.delegates(address(this)), address(0xFFF));
    }

    function testMintSuccessMinter(uint256 voltToMint) public {
        volt.mint(address(0xFFF), voltToMint);

        vm.prank(address(0xFFF));
        volt.delegate(address(0xFFF));

        assertEq(volt.totalSupply(), voltToMint);
        assertEq(volt.getCurrentVotes(address(0xFFF)), voltToMint);
        assertEq(volt.balanceOf(address(0xFFF)), voltToMint);
    }

    function testMintAfterDelegation(uint256 voltToMint) public {
        vm.assume(voltToMint < type(uint256).max / 2);
        volt.mint(address(0xFFF), voltToMint);

        vm.prank(address(0xFFF));
        volt.delegate(address(0xFFF));
        volt.mint(address(0xFFF), voltToMint);

        assertEq(volt.getCurrentVotes(address(0xFFF)), voltToMint * 2);
    }

    function testMintFailureUnauthorized() public {
        vm.startPrank(address(0xFFF));
        vm.expectRevert("Ownable: caller is not the owner");
        volt.mint(address(0xFFF), 1e18);
        vm.stopPrank();
    }

    function testMintFailToVoltContract() public {
        vm.expectRevert("Volt: cannot transfer to the volt contract");
        volt.mint(address(volt), 1e18);
    }

    function testMintFailZeroAddress() public {
        vm.expectRevert("Volt: cannot transfer to the zero address");
        volt.mint(address(0), 1e18);
    }

    function testBurn(uint256 voltToBurn) public {
        volt.mint(address(this), voltToBurn);
        volt.delegate(address(this));
        assertEq(volt.getCurrentVotes(address(this)), voltToBurn);

        volt.burn(voltToBurn);

        assertEq(volt.totalSupply(), 0);
        assertEq(volt.balanceOf(address(this)), 0);
        assertEq(volt.getCurrentVotes(address(this)), 0);
    }

    function testBurnFail() public {
        volt.mint(address(this), 1e18);

        vm.expectRevert("Volt: burn amount exceeds balance");
        volt.burn(2e18);
    }

    function testBurnFrom(uint256 voltToBurn) public {
        vm.assume(voltToBurn < type(uint256).max); // to make sure we don't run into infinite approval counter example
        address from = address(0xFFF);
        volt.mint(from, voltToBurn);

        vm.prank(from);
        volt.approve(address(this), voltToBurn);
        assertEq(volt.allowance(from, address(this)), voltToBurn);

        volt.burnFrom(from, voltToBurn);

        assertEq(volt.balanceOf(from), 0);
        assertEq(volt.allowance(from, address(this)), 0);
        assertEq(volt.totalSupply(), 0);
    }

    function testBurnFromInfiniteApproval(uint256 voltToBurn) public {
        address from = address(0xFFF);
        volt.mint(from, voltToBurn);

        vm.prank(from);
        volt.approve(address(this), type(uint256).max);
        assertEq(volt.allowance(from, address(this)), type(uint256).max);

        volt.burnFrom(from, voltToBurn);

        assertEq(volt.balanceOf(from), 0);
        assertEq(volt.allowance(from, address(this)), type(uint256).max);
        assertEq(volt.totalSupply(), 0);
    }

    function testBurnFromFailInsufficientBalance() public {
        address from = address(0xFFF);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 2e18);

        vm.expectRevert("Volt: burn amount exceeds balance");
        volt.burnFrom(from, 2e18);
    }

    function testBurnFromFailInsufficientAllowance() public {
        address from = address(0xFFF);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 0.9e18);

        vm.expectRevert(stdError.arithmeticError);
        volt.burnFrom(from, 1e18);
    }

    function testApprove(uint256 voltToApprove) public {
        assertTrue(volt.approve(address(0xFFF), voltToApprove));
        assertEq(volt.allowance(address(this), address(0xFFF)), voltToApprove);
    }

    function testTransfer(uint256 voltToTransfer) public {
        volt.mint(address(this), voltToTransfer);

        volt.transfer(address(0xFFF), voltToTransfer);

        assertEq(volt.totalSupply(), voltToTransfer);
        assertEq(volt.balanceOf(address(this)), 0);
        assertEq(volt.balanceOf(address(0xFFF)), voltToTransfer);
    }

    function testTransferFailInsufficientBalance() public {
        vm.expectRevert(stdError.arithmeticError);
        volt.transfer(address(0xFFF), 1e18);
    }

    function testTransferFailToVoltContract() public {
        vm.expectRevert("Volt: cannot transfer to the volt contract");
        volt.transfer(address(volt), 1e18);
    }

    function testTransferFrom(uint256 voltToTransfer) public {
        vm.assume(voltToTransfer < type(uint256).max); // to make sure we don't run into infinite approval counter example
        address from = address(0xFFF);
        volt.mint(from, voltToTransfer);

        vm.prank(from);
        volt.approve(address(this), voltToTransfer);
        assertEq(volt.allowance(from, address(this)), voltToTransfer);

        volt.transferFrom(from, address(this), voltToTransfer);

        assertEq(volt.balanceOf(from), 0);
        assertEq(volt.balanceOf(address(this)), voltToTransfer);
        assertEq(volt.allowance(from, address(this)), 0);
        assertEq(volt.totalSupply(), voltToTransfer);
    }

    function testTransferFromInfiniteApproval(uint256 voltToTransfer) public {
        address from = address(0xFFF);
        volt.mint(from, voltToTransfer);

        vm.prank(from);
        volt.approve(address(this), type(uint256).max);
        assertEq(volt.allowance(from, address(this)), type(uint256).max);

        volt.transferFrom(from, address(this), voltToTransfer);

        assertEq(volt.balanceOf(from), 0);
        assertEq(volt.balanceOf(address(this)), voltToTransfer);
        assertEq(volt.allowance(from, address(this)), type(uint256).max);
        assertEq(volt.totalSupply(), voltToTransfer);
    }

    function testTransferFromFailInsufficientBalance() public {
        address from = address(0xFFF);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 2e18);

        vm.expectRevert(stdError.arithmeticError);
        volt.transferFrom(from, address(this), 2e18);
    }

    function testTransferFromInsufficientAllowance() public {
        address from = address(0xFFF);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 0.9e18);

        vm.expectRevert(stdError.arithmeticError);
        volt.transferFrom(from, address(this), 1e18);
    }

    function testTransferFromFailToVoltContract() public {
        address from = address(0xFFF);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 1e18);

        vm.expectRevert("Volt: cannot transfer to the volt contract");
        volt.transferFrom(from, address(volt), 1e18);
    }

    function testPermit(uint256 voltToPermit) public {
        uint256 privateKey = 0xFFF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    getDomainSeperator(),
                    keccak256(
                        abi.encode(
                            volt.PERMIT_TYPEHASH(),
                            owner,
                            address(this),
                            voltToPermit,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        volt.permit(
            owner,
            address(this),
            voltToPermit,
            block.timestamp,
            v,
            r,
            s
        );

        assertEq(volt.allowance(owner, address(this)), voltToPermit);
        assertEq(volt.nonces(owner), 1);
    }

    function testPermitBadNonce() public {
        uint256 privateKey = 0xFFF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    getDomainSeperator(),
                    keccak256(
                        abi.encode(
                            volt.PERMIT_TYPEHASH(),
                            owner,
                            address(this),
                            1e18,
                            1,
                            block.timestamp
                        )
                    )
                )
            )
        );

        vm.expectRevert("Volt: unauthorized");
        volt.permit(owner, address(this), 1e18, block.timestamp, v, r, s);
    }

    function testPermitExpired() public {
        uint256 privateKey = 0xFFF;
        address owner = vm.addr(privateKey);

        uint256 timestamp = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    getDomainSeperator(),
                    keccak256(
                        abi.encode(
                            volt.PERMIT_TYPEHASH(),
                            owner,
                            address(this),
                            1e18,
                            0,
                            timestamp
                        )
                    )
                )
            )
        );

        vm.warp(timestamp + 1);
        vm.expectRevert("Volt: signature expired");
        volt.permit(owner, address(this), 1e18, timestamp, v, r, s);
    }

    function getDomainSeperator()
        internal
        view
        returns (bytes32 domainSeparator)
    {
        domainSeparator = keccak256(
            abi.encode(
                volt.DOMAIN_TYPEHASH(),
                keccak256(bytes(volt.name())),
                block.chainid,
                address(volt)
            )
        );
    }
}

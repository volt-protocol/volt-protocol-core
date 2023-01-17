//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "@forge-std/Test.sol";
import {Vm} from "@forge-std/Vm.sol";
import {Core} from "../../core/Core.sol";
import {VoltV2} from "../../volt/VoltV2.sol";
import {ICoreV2} from "../../core/ICoreV2.sol";
import {stdError} from "@forge-std/StdError.sol";
import {getCoreV2} from "./utils/Fixtures.sol";
import {TestAddresses as addresses} from "../unit/utils/TestAddresses.sol";

contract UnitTestVoltV2 is Test {
    using SafeCast for *;
    VoltV2 private volt;
    ICoreV2 private core;

    function setUp() public {
        core = getCoreV2();
        volt = new VoltV2(address(core));
    }

    function testTokenDetails() public {
        assertEq(volt.name(), "Volt");
        assertEq(volt.symbol(), "VOLT");
        assertEq(volt.decimals(), 18);
        assertEq(volt.totalSupply(), 0);
    }

    function testDelegate() public {
        address delegatee = address(0xFFF);
        volt.delegate(delegatee);
        assertEq(volt.delegates(address(this)), delegatee);
    }

    function testDelegateBySig() public {
        uint256 privateKey = 1;
        address delegatee = address(0xFFF);
        address owner = vm.addr(privateKey);

        assertEq(volt.nonces(owner), 0);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    getDomainSeperator(),
                    keccak256(
                        abi.encode(
                            volt.DELEGATION_TYPEHASH(),
                            delegatee,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        volt.delegateBySig(delegatee, 0, block.timestamp, v, r, s);

        assertEq(volt.nonces(owner), 1);
        assertEq(volt.delegates(owner), delegatee);
    }

    function testDelegateBySigInvalidSignature() public {
        uint256 privateKey = 1;
        address delegatee = address(0xFFF);
        address owner = vm.addr(privateKey);

        assertEq(volt.nonces(owner), 0);

        (uint8 v, , ) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    getDomainSeperator(),
                    keccak256(
                        abi.encode(
                            volt.DELEGATION_TYPEHASH(),
                            delegatee,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        vm.expectRevert("ECDSA: invalid signature");
        volt.delegateBySig(
            delegatee,
            0,
            block.timestamp,
            v,
            bytes32("insertsomerandom"),
            bytes32("insertsomerandom")
        );
    }

    function testDelegateBySigBadNonce() public {
        uint256 privateKey = 1;
        address delegatee = address(0xFFF);
        address owner = vm.addr(privateKey);

        assertEq(volt.nonces(owner), 0);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    getDomainSeperator(),
                    keccak256(
                        abi.encode(
                            volt.DELEGATION_TYPEHASH(),
                            delegatee,
                            1,
                            block.timestamp
                        )
                    )
                )
            )
        );

        vm.expectRevert("Volt: invalid nonce");
        volt.delegateBySig(delegatee, 1, block.timestamp, v, r, s);
    }

    function testDelegateBySigPastExpiry() public {
        uint256 privateKey = 1;
        address delegatee = address(0xFFF);
        address owner = vm.addr(privateKey);
        uint256 timestamp = block.timestamp;

        assertEq(volt.nonces(owner), 0);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    getDomainSeperator(),
                    keccak256(
                        abi.encode(
                            volt.DELEGATION_TYPEHASH(),
                            delegatee,
                            0,
                            timestamp
                        )
                    )
                )
            )
        );

        vm.warp(timestamp + 1);
        vm.expectRevert("Volt: signature expired");
        volt.delegateBySig(delegatee, 0, timestamp, v, r, s);
    }

    function testMintSuccessMinter(uint224 voltToMint) public {
        _testMintSupplyIncrease(address(0xFFF), voltToMint);

        assertEq(volt.getVotes(address(0xFFF)), 0);

        vm.prank(address(0xFFF));
        volt.delegate(address(0xFFF));

        assertEq(volt.totalSupply(), voltToMint);
        assertEq(volt.getVotes(address(0xFFF)), voltToMint);
        assertEq(volt.balanceOf(address(0xFFF)), voltToMint);
    }

    function testMintAfterDelegation(uint224 voltToMint) public {
        vm.assume(voltToMint < type(uint224).max / 2);

        _testMintSupplyIncrease(address(0xFFF), voltToMint);

        vm.prank(address(0xFFF));
        volt.delegate(address(0xFFF));

        _testMintSupplyIncrease(address(0xFFF), voltToMint);

        assertEq(volt.getVotes(address(0xFFF)), voltToMint * 2);
    }

    function testMintFailureUnauthorized() public {
        vm.startPrank(address(0xFFF));
        vm.expectRevert("CoreRef: Caller is not a minter");
        volt.mint(address(0xFFF), 1e18);
        vm.stopPrank();
    }

    function testMintFailToVoltContract() public {
        vm.startPrank(addresses.minterAddress);
        vm.expectRevert("Volt: cannot transfer to the volt contract");
        volt.mint(address(volt), 1e18);
        vm.stopPrank();
    }

    function testMintFailZeroAddress() public {
        vm.startPrank(addresses.minterAddress);
        vm.expectRevert("Volt: cannot transfer to the zero address");
        volt.mint(address(0), 1e18);
        vm.stopPrank();
    }

    function testMintFailOverflow() public {
        vm.startPrank(addresses.minterAddress);
        vm.expectRevert("Volt: total supply exceeds 224 bits");
        volt.mint(address(0xFFF), type(uint256).max);
        vm.stopPrank();
    }

    function testBurn(uint224 voltToBurn) public {
        _testMintSupplyIncrease(address(this), voltToBurn);

        assertEq(volt.getVotes(address(this)), 0);
        volt.delegate(address(this));
        assertEq(volt.delegates(address(this)), address(this));
        assertEq(volt.getVotes(address(this)), voltToBurn);

        volt.burn(voltToBurn);

        assertEq(volt.getVotes(address(this)), 0);

        assertEq(volt.totalSupply(), 0);
        assertEq(volt.delegates(address(this)), address(this));
        assertEq(volt.balanceOf(address(this)), 0);
        assertEq(volt.getVotes(address(this)), 0);
    }

    function testBurnFail() public {
        vm.prank(addresses.minterAddress);
        volt.mint(address(this), 1e18);

        vm.expectRevert("Volt: burn amount exceeds balance");
        volt.burn(2e18);
    }

    function testBurnFrom(uint224 voltToBurn) public {
        address from = address(0xFFF);
        _testMintSupplyIncrease(from, voltToBurn);

        vm.prank(from);
        volt.approve(address(this), voltToBurn);
        assertEq(volt.allowance(from, address(this)), voltToBurn);

        volt.burnFrom(from, voltToBurn);

        assertEq(volt.balanceOf(from), 0);
        assertEq(volt.allowance(from, address(this)), 0);
        assertEq(volt.totalSupply(), 0);
    }

    function testBurnFromInfiniteApproval(uint224 voltToBurn) public {
        address from = address(0xFFF);
        _testMintSupplyIncrease(from, voltToBurn);

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
        vm.prank(addresses.minterAddress);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 2e18);

        vm.expectRevert("Volt: burn amount exceeds balance");
        volt.burnFrom(from, 2e18);
    }

    function testBurnFromFailInsufficientAllowance() public {
        address from = address(0xFFF);
        vm.prank(addresses.minterAddress);
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

    function testTransfer(uint224 voltToTransfer) public {
        _testMintSupplyIncrease(address(this), voltToTransfer);

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

    function testTransferFrom(uint224 voltToTransfer) public {
        address from = address(0xFFF);
        _testMintSupplyIncrease(from, voltToTransfer);

        vm.prank(from);
        volt.approve(address(this), voltToTransfer);
        assertEq(volt.allowance(from, address(this)), voltToTransfer);

        volt.transferFrom(from, address(this), voltToTransfer);

        assertEq(volt.balanceOf(from), 0);
        assertEq(volt.balanceOf(address(this)), voltToTransfer);
        assertEq(volt.allowance(from, address(this)), 0);
        assertEq(volt.totalSupply(), voltToTransfer);
    }

    function testTransferFromInfiniteApproval(uint224 voltToTransfer) public {
        address from = address(0xFFF);
        _testMintSupplyIncrease(from, voltToTransfer);

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
        _testMintSupplyIncrease(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 2e18);

        vm.expectRevert(stdError.arithmeticError);
        volt.transferFrom(from, address(this), 2e18);
    }

    function testTransferFromInsufficientAllowance() public {
        address from = address(0xFFF);
        _testMintSupplyIncrease(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 0.9e18);

        vm.expectRevert(stdError.arithmeticError);
        volt.transferFrom(from, address(this), 1e18);
    }

    function testTransferFromFailToVoltContract() public {
        address from = address(0xFFF);
        _testMintSupplyIncrease(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 1e18);

        vm.expectRevert("Volt: cannot transfer to the volt contract");
        volt.transferFrom(from, address(volt), 1e18);
    }

    function testPermit(uint224 voltToPermit) public {
        uint256 privateKey = 0xFFF;
        address owner = vm.addr(privateKey);

        assertEq(volt.nonces(owner), 0);

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

    function testPermitInvalidSignature() public {
        uint256 privateKey = 0xFFF;
        address owner = vm.addr(privateKey);

        assertEq(volt.nonces(owner), 0);

        (uint8 v, , ) = vm.sign(
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
                            block.timestamp
                        )
                    )
                )
            )
        );

        vm.expectRevert("ECDSA: invalid signature");
        volt.permit(
            owner,
            address(this),
            1e18,
            block.timestamp,
            v,
            bytes32("insertsomerandom"),
            bytes32("insertsomerandom")
        );
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

    function testSetCore() public {
        vm.prank(addresses.governorAddress);
        volt.setCore(address(0x1234));

        assertEq(address(volt.core()), address(0x1234));
    }

    function testSetCoreFailsNonGovernor() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        volt.setCore(address(0x1234));
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

    function _testMintSupplyIncrease(
        address account,
        uint256 voltToTransfer
    ) public {
        uint256 startingBalance = volt.balanceOf(account);
        uint256 startingTotalSupply = volt.totalSupply();
        vm.prank(addresses.minterAddress);
        volt.mint(account, voltToTransfer);

        assertEq(volt.balanceOf(account), startingBalance + voltToTransfer);
        assertEq(volt.totalSupply(), startingTotalSupply + voltToTransfer);
    }
}

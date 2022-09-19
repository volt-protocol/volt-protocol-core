//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {DSTest} from "../unit/utils/DSTest.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {VoltV2} from "../../volt/VoltV2.sol";
import {Core} from "../../core/Core.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";

contract IntegrationTestVoltV2 is DSTest {
    VoltV2 private volt;
    Core private core = Core(MainnetAddresses.CORE);
    Vm private vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        volt = new VoltV2(MainnetAddresses.CORE);
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

    function testMintSuccessGovernor() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(address(0xFFF), 1e18);

        assertEq(volt.totalSupply(), 1e18);
        assertEq(volt.balanceOf(address(0xFFF)), 1e18);
    }

    function testMintSuccessMinter() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantMinter(address(this));

        volt.mint(address(0xFFF), 1e18);

        assertEq(volt.totalSupply(), 1e18);
        assertEq(volt.balanceOf(address(0xFFF)), 1e18);
    }

    function testMintFailure() public {
        vm.expectRevert("UNAUTHORIZED");
        volt.mint(address(0xFFF), 1e18);
    }

    function testBurn() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(address(this), 1e18);
        volt.burn(0.9e18);

        assertEq(volt.totalSupply(), 1e18 - 0.9e18);
        assertEq(volt.balanceOf(address(this)), 0.1e18);
    }

    function testBurnFail() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(address(this), 1e18);

        vm.expectRevert("Volt: burn amount exceeds balance");
        volt.burn(2e18);
    }

    function testBurnFrom() public {
        address from = address(0xFFF);
        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 1e18);
        assertEq(volt.allowance(from, address(this)), 1e18);

        volt.burnFrom(from, 1e18);

        assertEq(volt.balanceOf(from), 0);
        assertEq(volt.allowance(from, address(this)), 0);
        assertEq(volt.totalSupply(), 0);
    }

    function testBurnFromInfiniteApprovall() public {
        address from = address(0xFFF);
        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), type(uint96).max);
        assertEq(volt.allowance(from, address(this)), type(uint96).max);

        volt.burnFrom(from, 1e18);

        assertEq(volt.balanceOf(from), 0);
        assertEq(volt.allowance(from, address(this)), type(uint96).max);
        assertEq(volt.totalSupply(), 0);
    }

    function testBurnFromFailInsufficientBalance() public {
        address from = address(0xFFF);
        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 2e18);

        vm.expectRevert("Volt: burn amount exceeds balance");
        volt.burnFrom(from, 2e18);
    }

    function testBurnFromFailInsufficientAllowance() public {
        address from = address(0xFFF);

        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 0.9e18);

        vm.expectRevert("Volt: transfer amount exceeds spender allowance");
        volt.burnFrom(from, 1e18);
    }

    function testApprove() public {
        assertTrue(volt.approve(address(0xFFF), 1e18));

        assertEq(volt.allowance(address(this), address(0xFFF)), 1e18);
    }

    function testTransfer() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(address(this), 1e18);

        volt.transfer(address(0xFFF), 1e18);

        assertEq(volt.totalSupply(), 1e18);
        assertEq(volt.balanceOf(address(this)), 0);
        assertEq(volt.balanceOf(address(0xFFF)), 1e18);
    }

    function testTransferFailInsufficientBalance() public {
        vm.expectRevert("Volt: transfer amount exceeds balance");
        volt.transfer(address(0xFFF), 1e18);
    }

    function testTransferFrom() public {
        address from = address(0xFFF);
        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 1e18);
        assertEq(volt.allowance(from, address(this)), 1e18);

        volt.transferFrom(from, address(this), 1e18);

        assertEq(volt.balanceOf(from), 0);
        assertEq(volt.balanceOf(address(this)), 1e18);
        assertEq(volt.allowance(from, address(this)), 0);
        assertEq(volt.totalSupply(), 1e18);
    }

    function testTransferFromInfiniteApproval() public {
        address from = address(0xFFF);
        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), type(uint96).max);
        assertEq(volt.allowance(from, address(this)), type(uint96).max);

        volt.transferFrom(from, address(this), 1e18);

        assertEq(volt.balanceOf(from), 0);
        assertEq(volt.balanceOf(address(this)), 1e18);
        assertEq(volt.allowance(from, address(this)), type(uint96).max);
        assertEq(volt.totalSupply(), 1e18);
    }

    function testTransferFromFailInsufficientBalance() public {
        address from = address(0xFFF);
        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 2e18);

        vm.expectRevert("Volt: transfer amount exceeds balance");
        volt.transferFrom(from, address(this), 2e18);
    }

    function testTransferFromInsufficientAllowance() public {
        address from = address(0xFFF);

        vm.prank(MainnetAddresses.GOVERNOR);
        volt.mint(from, 1e18);

        vm.prank(from);
        volt.approve(address(this), 0.9e18);

        vm.expectRevert("Volt: transfer amount exceeds spender allowance");
        volt.transferFrom(from, address(this), 1e18);
    }

    function testPermit() public {
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
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        volt.permit(owner, address(this), 1e18, block.timestamp, v, r, s);

        assertEq(volt.allowance(owner, address(this)), 1e18);
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

    function getChainId() internal view returns (uint256) {
        uint256 chainId;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainId := chainid()
        }
        return chainId;
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
                getChainId(),
                address(volt)
            )
        );
    }
}

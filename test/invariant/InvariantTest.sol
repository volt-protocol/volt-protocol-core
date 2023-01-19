// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.13;

contract InvariantTest {
    address[] private targets;

    function targetContracts() public view virtual returns (address[] memory) {
        require(targets.length > 0, "NO_TARGET_CONTRACTS");

        return targets;
    }

    function addTargetContract(address newTargetContract) internal virtual {
        targets.push(newTargetContract);
    }
}

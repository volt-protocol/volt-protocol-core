// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {CoreRef} from "../refs/CoreRef.sol";

// Forked from Uniswap's UNI
// Reference: https://etherscan.io/address/0x1f9840a85d5af5bf1d1762f925bdaddc4201f984#code

contract VoltV2 is CoreRef {
    using SafeCast for *;

    /// @notice EIP-20 token name for this token
    // solhint-disable-next-line const-name-snakecase
    string public constant name = "Volt";

    /// @notice EIP-20 token symbol for this token
    // solhint-disable-next-line const-name-snakecase
    string public constant symbol = "VOLT";

    /// @notice EIP-20 token decimals for this token
    // solhint-disable-next-line const-name-snakecase
    uint8 public constant decimals = 18;

    /// @notice Total number of tokens in circulation
    // solhint-disable-next-line const-name-snakecase
    uint256 public totalSupply;

    /// @notice Allowance amounts on behalf of others
    mapping(address => mapping(address => uint256)) internal allowances;

    /// @notice Official record of token balances for each account
    mapping(address => uint256) internal balances;

    /// @notice A record of each accounts delegate
    mapping(address => address) public delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @notice hash digest for minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice hash digest for govern role
    bytes32 public constant GOVERN_ROLE = keccak256("GOVERN_ROLE");

    /// @notice A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice The EIP-712 typehash for the permit struct used by the contract
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    /// @notice A record of states for signing / validating signatures
    mapping(address => uint256) public nonces;

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    /// @notice The standard EIP-20 transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice The standard EIP-20 approval event
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    constructor(address core) CoreRef(core) {}

    /// @notice Mint new tokens
    /// @param dst The address of the destination account
    /// @param amount The number of tokens to be minted
    function mint(address dst, uint256 amount) external onlyMinter {
        require(dst != address(0), "Volt: cannot transfer to the zero address");
        require(
            dst != address(this),
            "Volt: cannot transfer to the volt contract"
        );

        totalSupply += amount;
        balances[dst] += amount;

        emit Transfer(address(0), dst, amount);

        /// If an address is being minted to for the first time as the src address
        /// is address(0) the srcRep logic will not be executed, and as the user
        /// will not have delegated at this point in time, the dstRep logic will
        /// not be executed. However, if the user has a Volt balance, and has delegated
        /// either themselves or another address, the dstRep logic will be executed
        /// and the voting power will increase to the delegate by the minted amount
        _moveDelegates(address(0), delegates[dst], amount);
    }

    /// @notice Burns the amount of the callers tokens
    /// @param amount The amount of tokens to be burned
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Burns tokens amount of tokens from 'src' address deducting\
    /// from the callers allowance
    /// @param src The address the tokens will be burned from
    /// @param amount The amount of tokens to be burned
    function burnFrom(address src, uint256 amount) external {
        _spendAllowance(src, amount);
        _burn(src, amount);
    }

    /// @notice Get the number of tokens `spender` is approved to spend on behalf of `account`
    /// @param owner The address of the account holding the funds
    /// @param spender The address of the account spending the funds
    /// @return The number of tokens approved
    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return allowances[owner][spender];
    }

    /// @notice Approve `spender` to transfer up to `amount` from `src`
    /// @dev This will overwrite the approval amount for `spender`
    ///  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
    /// @param spender The address of the account which may transfer tokens
    /// @param amount The number of tokens that are approved (2^256-1 means infinite)
    /// @return Whether or not the approval succeeded
    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Triggers an approval from owner to spends
    /// @param owner The address to approve from
    /// @param spender The address to be approved
    /// @param amount The number of tokens that are approved (2^256-1 means infinite)
    /// @param deadline The time at which to expire the signature
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                block.chainid,
                address(this)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                amount,
                nonces[owner]++,
                deadline
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "Volt: invalid signature");
        require(signatory == owner, "Volt: unauthorized");
        require(block.timestamp <= deadline, "Volt: signature expired");

        allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    /// @notice Get the number of tokens held by the `account`
    /// @param account The address of the account to get the balance of
    /// @return The number of tokens held
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    /// @notice Transfer `amount` tokens from `msg.sender` to `dst`
    /// @param dst The address of the destination account
    /// @param amount The number of tokens to transfer
    /// @return Whether or not the transfer succeeded
    function transfer(address dst, uint256 amount) external returns (bool) {
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    /// @notice Transfer `amount` tokens from `src` to `dst`
    /// @param src The address of the source account
    /// @param dst The address of the destination account
    /// @param amount The number of tokens to transfer
    /// @return Whether or not the transfer succeeded
    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external returns (bool) {
        _spendAllowance(src, amount);
        _transferTokens(src, dst, amount);
        return true;
    }

    /// @notice Delegate votes from `msg.sender` to `delegatee`
    /// @param delegatee The address to delegate votes to
    function delegate(address delegatee) public {
        return _delegate(msg.sender, delegatee);
    }

    /// @notice Delegates votes from signatory to `delegatee`
    /// @param delegatee The address to delegate votes to
    /// @param nonce The contract state required to match the signature
    /// @param expiry The time at which to expire the signature
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                block.chainid,
                address(this)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "Volt: invalid signature");
        require(nonce == nonces[signatory]++, "Volt: invalid nonce");
        require(block.timestamp <= expiry, "Volt: signature expired");
        return _delegate(signatory, delegatee);
    }

    /// @notice Gets the current votes balance for `account`
    /// @param account The address to get votes balance
    /// @return The number of current votes for `account`
    function getCurrentVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = numCheckpoints[account];
        return
            nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /// @notice Determine the prior number of votes for an account as of a block number
    /// @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
    /// @param account The address of the account to check
    /// @param blockNumber The block number to get the vote balance at
    /// @return The number of votes the account had as of the given block
    function getPriorVotes(address account, uint256 blockNumber)
        public
        view
        returns (uint256)
    {
        require(blockNumber < block.number, "Volt: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _burn(address src, uint256 amount) internal {
        require(balances[src] >= amount, "Volt: burn amount exceeds balance");

        totalSupply -= amount;
        balances[src] -= amount;

        emit Transfer(src, address(0), amount);

        _moveDelegates(delegates[src], address(0), amount);
    }

    function _spendAllowance(address src, uint256 amount) internal {
        address spender = msg.sender;
        uint256 spenderAllowance = allowances[src][spender];

        if (spender != src && spenderAllowance != type(uint256).max) {
            uint256 newAllowance = spenderAllowance - amount;
            allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint256 delegatorBalance = balances[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _transferTokens(
        address src,
        address dst,
        uint256 amount
    ) internal {
        require(
            dst != address(this),
            "Volt: cannot transfer to the volt contract"
        );

        balances[src] -= amount;
        balances[dst] += amount;

        emit Transfer(src, dst, amount);

        _moveDelegates(delegates[src], delegates[dst], amount);
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint256 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0
                    ? checkpoints[srcRep][srcRepNum - 1].votes
                    : 0;

                uint256 srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0
                    ? checkpoints[dstRep][dstRepNum - 1].votes
                    : 0;

                uint256 dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    ) internal {
        uint32 blockNumber = block.number.toUint32();
        if (
            nCheckpoints != 0 &&
            checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber
        ) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(
                blockNumber,
                newVotes
            );
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
    IntlDeferredVault (POC)

    IRL problem:
    - International student-athletes on F-1 visas cannot casually earn NIL income
    while physically in the US without risking immigration problems.
    - They still have brands/sponsors who WANT to support them long-term.

    Solution:
    - Sponsor deposit into a deferred vault for a specific athlete.
    - Funds are locked under conservative conditions:
        * Time-based unlock (e.g. after expected graduation date), OR
        * Oracle-based approval (e.g. off-chain legal/compliance confirms the athlete 
        is in a status/location where patment is safe).
    - Athlete can only withdraw once conditions are met.

    Notes:
    - This contract does NOT encode imigration law.
    -It just gives a conservative technical structure to hold money now and release it later when condittions
    are met.

    Recommended use:
    - Deploy on a cheap EVM L2 (Base, Polygon, Arbitrum, Optimism).
    - Use a stablecoin (USDC, USDT, etc.) as 'token'.

*/

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract IntlDeferredVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --------- DATA STRUCTURES ---------

    struct Grant {
        address athlete;
        address sponsor;
        uint256 amount; // Amount of ERC20 tokens locked
        uint64 unlockTime; // No withdrawals before this timestamp
        bytes32 metadataHash; // IPFS CID or hash of off-chain NIL agreement
        bool oracleApproved;
        bool withdrawn;
    }

    // ERC20 token used for all deposits (e.g., USDC on Base/Polygon)
    IERC20 public immutable token;

    // All grants (each deposit is its own "grant")
    Grant[] public grants;

    // Oracle role: addresses allowed to flip oracleApproved
    mapping(address => bool) public isOracle;

    // --------- EVENTS ---------

    event OracleUpdated(address indexed oracle, bool allowed);

    event GrantCreated(
        uint256 indexed grantId,
        address indexed sponsor,
        address indexed athlete,
        uint256 amount,
        uint64 unlockTime,
        bytes32 metadataHash
    );

    event OracleApproved(uint256 indexed grantId, address indexed oracle);

    event Withdrawn(
        uint256 indexed grantId,
        address indexed athlete,
        uint256 amount
    );

    event Refunded(
        uint256 indexed grantId,
        address indexed sponsor,
        uint256 amount
    );

    // --------- MODIFIERS ---------

    modifier onlyOracle() {
        require(
            isOracle[msg.sender],
            "IntlDeferredVault: not an authorized oracle"
        );
        _;
    }

    // --------- CONSTRUCTOR ---------

    /**
     * @param tokenAddress ERC20 token to use for all deposits (e.g., USDC)
     * @param initialOracles Initial list of oracle addresses (compliance, legal, Chainlink relays).
     */
    constructor(address tokenAddress, address[] memory initialOracles) Ownable(msg.sender) {
        require(
            tokenAddress != address(0),
            "IntlDeferredVault: zero token address"
        );
        token = IERC20(tokenAddress);

        for (uint256 i = 0; i < initialOracles.length; i++) {
            isOracle[initialOracles[i]] = true;
            emit OracleUpdated(initialOracles[i], true);
        }
    }

    // --------- ORACLE MANAGEMENT ---------

    /**
     * @notice Owner (platform) manages which addresses are allowed to act as oracles.
     * @dev Oracles are trusted entities that signal when off-chain conditions are met for withdrawal.
     */
    function setOracle(address oracle, bool allowed) external onlyOwner {
        isOracle[oracle] = allowed;
        emit OracleUpdated(oracle, allowed);
    }

    // --------- CORE LOGIC ---------

    /**
     * @notice Sponsor deposits funds for an athlete into the deferred vault.
     *
     * @param athlete The athlete who will eventually be allowed to withdraw.
     * @param amount Amount of tokens to deposit (must have been approved first).
     * @param unlockTime Minumun timestamp before the athlete can withdraw based on time.
     * @param metadataHash IPFS CID or hash of the off-chain NIL agreement/terms.
     *
     * Flow:
     * - Sponsor calls 'approve()' on the ERC20 token for this contract.
     * - Then calls 'depositFor(...)' .
     * - Tokens are transferred from sponsor to this contract and locked until conditions are met.
     */
    function depositFor(
        address athlete,
        uint256 amount,
        uint64 unlockTime,
        bytes32 metadataHash
    ) external nonReentrant returns (uint256 grantId) {
        require(athlete != address(0), "IntlDeferredVault: zero athlete");
        require(amount > 0, "IntlDeferredVault: zero amount");
        require(
            unlockTime > block.timestamp,
            "IntlDeferredVault: invalid unlock time"
        );

        // Transfer tokens from sponsor to vault
        token.safeTransferFrom(msg.sender, address(this), amount);

        Grant memory newGrant = Grant({
            athlete: athlete,
            sponsor: msg.sender,
            amount: amount,
            unlockTime: unlockTime,
            metadataHash: metadataHash,
            oracleApproved: false,
            withdrawn: false
        });

        grants.push(newGrant);
        grantId = grants.length - 1;

        emit GrantCreated(
            grantId,
            msg.sender,
            athlete,
            amount,
            unlockTime,
            metadataHash
        );
    }

    /**
     * @notice Oracle signals that off-chain conditions are satisfied
     *     for this grant (e.g. athlete is no longer in restricted status/location).
     *
     * @dev This does NOT transfer any funds; it just marks the grant as eligible to withdraw from oracle
     * perspective.
     */
    function approveForWithdrawal(uint256 grantId) external onlyOracle {
        require(grantId < grants.length, "IntlDeferredVault: invalid grantId");

        Grant storage grant = grants[grantId];
        require(!grant.withdrawn, "IntlDeferredVault: already withdrawn");

        grant.oracleApproved = true;

        emit OracleApproved(grantId, msg.sender);
    }

    /**
     * @notice Athlete withdraws their deferred NIL funds once conditions are met.
     *
     * Conditions:
     * - Caller is the athlete for this grant.
     * - Grant not already withdrawn.
     * - Amount > 0.
     * - Either:
     *     * Current time >= unlockTime  (time-based unlock), OR
     *     * oracleApproved == true     (oracle-based approval).
     */
    function withdraw(uint256 grantId) external nonReentrant {
        require(grantId < grants.length, "IntlDeferredVault: invalid grantId");

        Grant storage grant = grants[grantId];
        require(msg.sender == grant.athlete, "IntlDeferredVault: not athlete");
        require(!grant.withdrawn, "IntlDeferredVault: already withdrawn");
        require(grant.amount > 0, "IntlDeferredVault: zero amount");

        bool timeOk = block.timestamp >= grant.unlockTime;
        bool oracleOk = grant.oracleApproved;

        require(timeOk || oracleOk, "IntlDeferredVault: conditions not met");

        uint256 amount = grant.amount;
        grant.amount = 0; // prevent re-entrancy
        grant.withdrawn = true;

        token.safeTransfer(grant.athlete, amount);

        emit Withdrawn(grantId, grant.athlete, amount);
    }

    /**
     * @notice Optional escape hatch: refund back to sponsor in exceptional cases.
     *
     * @dev Only owner (platform/DAO) can do this, and only if:
     *          - Grant not already withdrawn.
     *          - There are still funds.
     *
     * Real-world use:
     * - If NIL agreement is voided or impossible to execute for legal reasons,
     *   platform can return the funds to the sponsor..
     *
     * Governance:
     * -  In production, you might gate this via a DAO vote or multisig, not a single owner.
     */
    function refundToSponsor(uint256 grantId) external onlyOwner nonReentrant {
        require(grantId < grants.length, "IntlDeferredVault: invalid grantId");

        Grant storage grant = grants[grantId];
        require(!grant.withdrawn, "IntlDeferredVault: already withdrawn");
        require(grant.amount > 0, "IntlDeferredVault: zero amount");

        uint256 amount = grant.amount;
        grant.amount = 0; // prevent re-entrancy
        grant.withdrawn = true; // treat as resolved

        token.safeTransfer(grant.sponsor, amount);

        emit Refunded(grantId, grant.sponsor, amount);
    }

    // --------- VIEW HELPERS ---------

    function grantsCount() external view returns (uint256) {
        return grants.length;
    }

    function getGrant(uint256 grantId) external view returns (Grant memory) {
        require(grantId < grants.length, "IntlDeferredVault: invalid grantId");
        return grants[grantId];
    }
}

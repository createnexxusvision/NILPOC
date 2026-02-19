// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
    TrickBountyPool (POC)

    IRL problem (extreme sports):
    - Athletes risk their bodies for stunt contests, street lines, downhill runs.
    - Payouts are often opaque, winner-take-all, and safety rarely has direct $$$ incentives.

    Solution:
    - Sponsors fund an on-chain prize pool for an event.
    - Organizer defines "bounties" (trick, line, safety bonus) with % of the pool.
    - Judges attest on-chain which athlete hit which bounty.
    - Contract automatically pays that share of the pool to the athlete.

    Design (v1):
    - Single ERC20 token (e.g., USDC on Base/Polygon/Arbitrum Nova).
    - Pool funded BEFORE the event, then "locked" by the organizer.
    - Each bounty has a poolBps (basis points) share of the locked pool.
      (Sum of all bounties' poolBps <= 10000 == 100% of pool)
    - Once locked, funding cannot change. Leftover pool can be withdrawn by owner after event.
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TrickBountyPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ----------------- DATA STRUCTURES -----------------

    struct Bounty {
        uint16 poolBps; // share of lockedPool in basis points (10000 = 100%)
        bool claimed; // has this bounty already been claimed?
        address winner; // which athlete was marked as the winner
        bytes32 descriptionHash; // IPFS hash / description of this bounty
    }

    // ERC20 used for all funding and payouts (e.g. USDC)
    IERC20 public token;

    // Total prize pool locked for this event
    uint256 public lockedPool;

    // Have we locked the pool (no more funding/major structure changes)?
    bool public poolLocked;

    // Sum of all bounty poolBps (must be <= 10000)
    uint16 public totalBpsUsed;

    // List of bounties
    Bounty[] public bounties;

    // Athletes allowed to receive payouts in this event
    mapping(address => bool) public isAthlete;

    // Judges allowed to mark bounties as completed
    mapping(address => bool) public isJudge;

    // ----------------- EVENTS -----------------

    event TokenUpdated(address indexed token);
    event Funded(address indexed sponsor, uint256 amount);
    event PoolLocked(uint256 lockedPool);
    event AthleteRegistered(address indexed athlete, bool allowed);
    event JudgeUpdated(address indexed judge, bool allowed);

    event BountyCreated(
        uint256 indexed bountyId,
        uint16 poolBps,
        bytes32 descriptionHash
    );

    event BountyCompleted(
        uint256 indexed bountyId,
        address indexed athlete,
        uint256 payoutAmount
    );

    event LeftoverWithdrawn(address indexed to, uint256 amount);

    // ----------------- MODIFIERS -----------------

    modifier onlyJudge() {
        require(isJudge[msg.sender], "TrickBountyPool: not judge");
        _;
    }

    modifier beforeLock() {
        require(!poolLocked, "TrickBountyPool: pool locked");
        _;
    }

    modifier afterLock() {
        require(poolLocked, "TrickBountyPool: pool not locked");
        _;
    }

    // ----------------- CONSTRUCTOR -----------------

    /**
     * @param tokenAddress ERC20 token address (e.g. USDC on Base/Polygon).
     */
    constructor(address tokenAddress) Ownable(msg.sender) {
        require(tokenAddress != address(0), "TrickBountyPool: zero token");
        token = IERC20(tokenAddress);
        emit TokenUpdated(tokenAddress);
    }

    // ----------------- ADMIN SETUP -----------------

    /**
     * @notice Update ERC20 token (e.g., move from test token to real USDC).
     * @dev Only allowed before the pool is locked.
     */
    function setToken(address newToken) external onlyOwner beforeLock {
        require(newToken != address(0), "TrickBountyPool: zero token");
        token = IERC20(newToken);
        emit TokenUpdated(newToken);
    }

    /**
     * @notice Register or remove an athlete for this event.
     */
    function setAthlete(
        address athlete,
        bool allowed
    ) external onlyOwner beforeLock {
        require(athlete != address(0), "TrickBountyPool: zero athlete");
        isAthlete[athlete] = allowed;
        emit AthleteRegistered(athlete, allowed);
    }

    /**
     * @notice Set or unset a judge wallet.
     */
    function setJudge(address judge, bool allowed) external onlyOwner {
        require(judge != address(0), "TrickBountyPool: zero judge");
        isJudge[judge] = allowed;
        emit JudgeUpdated(judge, allowed);
    }

    // ----------------- FUNDING & LOCKING -----------------

    /**
     * @notice Sponsors call this to fund the prize pool BEFORE it is locked.
     *         They must approve this contract for `amount` on the ERC20 token first.
     */
    function fundPool(uint256 amount) external beforeLock nonReentrant {
        require(amount > 0, "TrickBountyPool: zero amount");
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    /**
     * @notice Owner locks the pool once funding and bounties are finalized.
     *
     * Effects:
     * - Sets lockedPool = current token balance.
     * - Prevents more funding and major structural changes.
     */
    function lockPool() external onlyOwner beforeLock {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "TrickBountyPool: no funds");
        require(totalBpsUsed <= 10000, "TrickBountyPool: totalBpsUsed > 100%");
        lockedPool = balance;
        poolLocked = true;

        emit PoolLocked(lockedPool);
    }

    // ----------------- BOUNTY MANAGEMENT -----------------

    /**
     * @notice Create a new bounty for the event.
     *
     * @param poolBps        Share of the locked pool in basis points (10000 = 100%).
     * @param descriptionHash IPFS hash / off-chain description of the bounty:
     *                        e.g., "First to land switch 360 over big gap".
     *
     * Requirements:
     * - totalBpsUsed + poolBps <= 10000 (never over-allocate the pool).
     * - Only callable before the pool is locked.
     */
    function createBounty(
        uint16 poolBps,
        bytes32 descriptionHash
    ) external onlyOwner beforeLock returns (uint256 bountyId) {
        require(poolBps > 0, "TrickBountyPool: zero bps");
        require(
            totalBpsUsed + poolBps <= 10000,
            "TrickBountyPool: exceeds 100%"
        );

        bountyId = bounties.length;
        bounties.push(
            Bounty({
                poolBps: poolBps,
                claimed: false,
                winner: address(0),
                descriptionHash: descriptionHash
            })
        );

        totalBpsUsed += poolBps;

        emit BountyCreated(bountyId, poolBps, descriptionHash);
    }

    // ----------------- JUDGE FLOW / PAYOUTS -----------------

    /**
     * @notice Judge marks a bounty as completed by an athlete.
     *
     * @param bountyId ID of the bounty to award.
     * @param athlete  Athlete address that completed this bounty.
     *
     * Flow:
     * - Can only be called by a judge.
     * - Bounty must not have been claimed before.
     * - Pool must be locked.
     * - Athlete must be registered.
     * - Contract calculates payout = lockedPool * poolBps / 10000.
     * - Sends payout to athlete and records winner.
     */

    function completeBounty(
        uint256 bountyId,
        address athlete
    ) external onlyJudge afterLock nonReentrant {
        require(bountyId < bounties.length, "TrickBountyPool: invalid bounty");
        Bounty storage b = bounties[bountyId];
        require(!b.claimed, "TrickBountyPool: already claimed");
        require(isAthlete[athlete], "TrickBountyPool: not athlete");

        uint256 payout = (lockedPool * b.poolBps) / 10000;
        b.claimed = true;
        b.winner = athlete;

        token.safeTransfer(athlete, payout);
        emit BountyCompleted(bountyId, athlete, payout);
    }
}

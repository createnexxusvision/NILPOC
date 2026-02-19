// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
    ClipRevenueSplitter (POC)

    IRL problem:
    - Viral sports/gaming clips are a team effort:
        * athlete
        * filmer
        * editor
        * musician, etc.
      But the money usually flows to just one person.

    Solution:
    - Register each "clip" on-chain with a list of contributors + basis point splits.
    - When revenue comes in (sponsor payment, ad rev share, NFT royalties),
      the payer calls distributeForClip(clipId, amount).
    - Contract pulls ERC20 tokens from the payer,
      and immediately sends each contributor their share.

    v1:
    - Single ERC20 token (e.g. USDC).
    - Simple, per-clip, on-demand distribution.
    - No balances are stored; everything is forwarded.

    v2 ideas:
    - Link clipId to an NFT (tokenId).
    - Add ability to update splits with multi-sig consent.
    - Subgraph indexer to show lifetime revenue per contributor per clip.
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ClipRevenueSplitter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ----------------- DATA STRUCTURES -----------------

    struct Contributor {
        address wallet;
        uint96 bps; // basis points: 10000 = 100%
    }

    struct Clip {
        bool exists;
        uint16 contributorCount;
        // contributors stored in a separate mapping: clipId => index => Contributor
    }

    // ERC20 token used for all distributions (e.g. USDC on Base/Polygon)
    IERC20 public token;

    // clipId => Clip metadata
    mapping(uint256 => Clip) public clips;

    // clipId => index => Contributor
    mapping(uint256 => mapping(uint256 => Contributor)) public clipContributors;

    // For convenience, keep a running clip counter if you want auto-IDs
    uint256 public nextClipId = 1;

    // ----------------- EVENTS -----------------

    event TokenUpdated(address indexed newToken);

    event ClipCreated(uint256 indexed clipId, uint16 contributorCount);

    event ClipContributorsSet(
        uint256 indexed clipId,
        address[] wallets,
        uint96[] bps
    );

    event RevenueDistributed(
        uint256 indexed clipId,
        address indexed payer,
        uint256 amount
    );

    // ----------------- CONSTRUCTOR -----------------

    /**
     * @param tokenAddress ERC20 token used for payments (e.g. USDC).
     */
    constructor(address tokenAddress) Ownable(msg.sender) {
        require(tokenAddress != address(0), "ClipSplitter: zero token");
        token = IERC20(tokenAddress);
        emit TokenUpdated(tokenAddress);
    }

    // ----------------- ADMIN -----------------

    /**
     * @notice Owner can update the ERC20 token if needed (e.g., migrate from test token to real USDC).
     */
    function setToken(address newToken) external onlyOwner {
        require(newToken != address(0), "ClipSplitter: zero token");
        token = IERC20(newToken);
        emit TokenUpdated(newToken);
    }

    // ----------------- CLIP REGISTRATION -----------------

    /**
     * @notice Create a new clip and set its contributors + splits.
     *
     * @param wallets Array of contributor addresses (athlete, filmer, editor, etc.).
     * @param bps     Array of basis point splits (must match wallets length).
     *
     * Requirements:
     * - wallets.length == bps.length
     * - sum(bps) == 10000 (i.e., 100%)
     *
     * Returns:
     * - clipId (uint256) to be used later when distributing revenue.
     */
    function createClip(
        address[] calldata wallets,
        uint96[] calldata bps
    ) external onlyOwner returns (uint256 clipId) {
        require(wallets.length > 0, "ClipSplitter: no contributors");
        require(wallets.length == bps.length, "ClipSplitter: length mismatch");

        uint256 totalBps;
        for (uint256 i = 0; i < bps.length; i++) {
            require(wallets[i] != address(0), "ClipSplitter: zero wallet");
            totalBps += bps[i];
        }
        require(totalBps == 10000, "ClipSplitter: bps != 100%");

        clipId = nextClipId;
        nextClipId++;

        Clip storage c = clips[clipId];
        require(!c.exists, "ClipSplitter: clip exists");

        c.exists = true;
        c.contributorCount = uint16(wallets.length);

        for (uint256 i = 0; i < wallets.length; i++) {
            clipContributors[clipId][i] = Contributor({
                wallet: wallets[i],
                bps: bps[i]
            });
        }

        emit ClipCreated(clipId, c.contributorCount);
        emit ClipContributorsSet(clipId, wallets, bps);
    }

    /**
     * @notice (Optional) Update contributors for an existing clip.
     *         Useful if you fix a mistake or renegotiate splits.
     *
     *         In production, you probably want multi-party consent instead of onlyOwner.
     */
    function updateClipContributors(
        uint256 clipId,
        address[] calldata wallets,
        uint96[] calldata bps
    ) external onlyOwner {
        Clip storage c = clips[clipId];
        require(c.exists, "ClipSplitter: clip not found");
        require(wallets.length > 0, "ClipSplitter: no contributors");
        require(wallets.length == bps.length, "ClipSplitter: length mismatch");

        uint256 totalBps;
        for (uint256 i = 0; i < bps.length; i++) {
            require(wallets[i] != address(0), "ClipSplitter: zero wallet");
            totalBps += bps[i];
        }
        require(totalBps == 10000, "ClipSplitter: bps != 100%");

        // Overwrite with new contributors
        for (uint256 i = 0; i < wallets.length; i++) {
            clipContributors[clipId][i] = Contributor({
                wallet: wallets[i],
                bps: bps[i]
            });
        }

        // If new list is shorter than old, we could leave old entries as junk;
        // but they won't be read because contributorCount was updated.

        emit ClipContributorsSet(clipId, wallets, bps);
    }

    // ----------------- REVENUE DISTRIBUTION -----------------

    /**
     * @notice Distribute revenue for a given clipId.
     *
     * @param clipId ID of the clip whose contributors should be paid.
     * @param amount Amount of ERC20 tokens to distribute.
     *
     * Flow:
     * - Payer calls token.approve(this, amount).
     * - Then calls distributeForClip(clipId, amount).
     * - Contract pulls tokens from payer.
     * - Immediately splits and sends to each contributor wallet according to bps.
     */
    function distributeForClip(
        uint256 clipId,
        uint256 amount
    ) external nonReentrant {
        require(amount > 0, "ClipSplitter: zero amount");

        Clip storage c = clips[clipId];
        require(c.exists, "ClipSplitter: clip not found");

        // Pull tokens from payer into this contract
        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 remaining = amount;
        uint16 count = c.contributorCount;

        // Distribute according to bps
        for (uint256 i = 0; i < count; i++) {
            Contributor memory contrib = clipContributors[clipId][i];
            uint256 share = (amount * contrib.bps) / 10000;

            if (share > 0) {
                remaining -= share;
                token.safeTransfer(contrib.wallet, share);
            }
        }

        // Any tiny rounding remainder stays in the contract as dust.
        // You can add a function later to sweep dust to a treasury.

        emit RevenueDistributed(clipId, msg.sender, amount);
    }

    // ----------------- VIEW HELPERS -----------------

    /**
     * @notice Returns all contributors and their bps for a clip.
     *         (Convenience view for front-ends; not gas-efficient on-chain.)
     */
    function getClipContributors(
        uint256 clipId
    ) external view returns (address[] memory wallets, uint96[] memory bps) {
        Clip storage c = clips[clipId];
        require(c.exists, "ClipSplitter: clip not found");

        uint16 count = c.contributorCount;
        wallets = new address[](count);
        bps = new uint96[](count);

        for (uint256 i = 0; i < count; i++) {
            Contributor memory contrib = clipContributors[clipId][i];
            wallets[i] = contrib.wallet;
            bps[i] = contrib.bps;
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
    PatronStream

    IRL problem:
    - Non=revenue athletes are broke.
    - They have 50-500 people who would send them $5-$20/month if it were easy + transparent.

    Solution:
    - Fans "support" an athlete by sewnding ERC20 tokens (e.g. USDC) into this contract.
    - Contract tracks:
        * how much each athlete has received (withdrawable balance)
        * how much each supporter has sent to a given athlete (for transparency)
    - Athlete can withdraw their accumulated balance at any time.
    - Optional: first-time supporters get an ERC721 patron badge NFT.

    Notes:
    - v1 is simple: no continuous streaming, just discrete top-ups.
    - "Recurring" behavior is created by:
        *  Fans calling support() repeatedly, OR
        *  An off-chain scheduler (bot, script) triggering support() on a schedule.
        
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PatronStream is ERC721, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ------------ DATA STRUCTURES ------------

    struct SupportRecord {
        uint256 totalSupported; // lifetime total this supporter sent to this athlete
        uint256 lastAmount; // last amount sent in a single support() call
        uint64 lastTimestamp; // time of last support
        uint8 lastTier; // user-defined tier (1=bronze,2=silver,3=gold, etc.)
        bytes32 lastMetadata; // optional hash / IPFS CID describing the support reason
        bool exists; // marks if this supporter has ever supported this athlete
    }

    // ERC20 token used for all support payments (e.g. USDC on Polygon/Base)
    IERC20 public immutable token;

    // Athlete address => withdrawable balance (in `token`)
    mapping(address => uint256) public athleteBalance;

    // Athlete => Supporter => SupportRecord
    mapping(address => mapping(address => SupportRecord)) public supportInfo;

    // Optional NFT badge: did this supporter already get a badge for this athlete?
    mapping(address => mapping(address => bool)) public hasBadge; // athlete => supporter => bool

    // Simple tokenId counter for ERC721
    uint256 private _nextTokenId = 1;

    // Enable/disable NFT minting
    bool public badgesEnabled;

    // ----------------- EVENTS -----------------

    event Supported(
        address indexed supporter,
        address indexed athlete,
        uint256 amount,
        uint8 tier,
        bytes32 metadata
    );

    event Withdrawn(address indexed athlete, uint256 amount);

    event BadgeMinted(
        uint256 indexed tokenId,
        address indexed supporter,
        address indexed athlete
    );

    event BadgesEnabled(bool enabled);

    // ----------------- CONSTRUCTOR -----------------

    /**
     * @param tokenAddress ERC20 token used for support (e.g. USDC).
     * @param _badgesEnabled Whether to mint patron badge NFTs for first-time supporters.
     */
    constructor(
        address tokenAddress,
        bool _badgesEnabled
    ) ERC721("Patron Badge", "PTNBDG") {
        require(tokenAddress != address(0), "PatronStream: zero token");
        token = IERC20(tokenAddress);
        badgesEnabled = _badgesEnabled;
        emit BadgesEnabled(_badgesEnabled);
    }

    // ----------------- CORE LOGIC -----------------

    /**
     * @notice Fan/supporter sends tokens to support a specific athlete.
     *
     * @param athlete The athlete's wallet address.
     * @param amount  Amount of tokens to send (must approve this contract first).
     * @param tier    An arbitrary tier number (e.g., 1=bronze, 2=silver, 3=gold).
     * @param metadata Optional hash / IPFS CID representing message, campaign, etc.
     *
     * Flow:
     * - Supporter calls `token.approve(address(this), amount)` on the ERC20 token.
     * - Then calls `support(athlete, amount, tier, metadata)`.
     * - Tokens move from supporter to this contract, and the athlete's balance increases.
     * - We update supporter -> athlete stats, and optionally mint a badge NFT.
     */
    function support(
        address athlete,
        uint256 amount,
        uint8 tier,
        bytes32 metadata
    ) external nonReentrant {
        require(athlete != address(0), "PatronStream: zero athlete");
        require(amount > 0, "PatronStream: zero amount");
        require(athlete != address(this), "PatronStream: invalid athlete");

        // Pull tokens from supporter
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Update athlete's withdrawable balance
        athleteBalance[athlete] += amount;

        // Update supporter record
        SupportRecord storage record = supportInfo[athlete][msg.sender];

        record.totalSupported += amount;
        record.lastAmount = amount;
        record.lastTimestamp = uint64(block.timestamp);
        record.lastTier = tier;
        record.lastMetadata = metadata;
        record.exists = true;

        // Mint a badge if enabled and supporter doesn't have one for this athlete yet
        if (badgesEnabled && !hasBadge[athlete][msg.sender]) {
            _mintBadge(msg.sender, athlete);
        }

        emit Supported(msg.sender, athlete, amount, tier, metadata);
    }

    /**
     * @notice Athlete withdraws tokens that have been supported to them.
     *
     * @param amount Amount to withdraw. Use max uint256 to withdraw all.
     *
     * Flow:
     * - Athlete calls withdraw() from their athlete wallet.
     * - Contract transfers tokens from itself to the athlete.
     */
    function withdraw(uint256 amount) external nonReentrant {
        uint256 balance = athleteBalance[msg.sender];
        require(balance > 0, "PatronStream: no balance");

        uint256 toWithdraw = amount;
        if (amount == type(uint256).max) {
            toWithdraw = balance;
        } else {
            require(amount <= balance, "PatronStream: amount exceeds balance");
        }

        athleteBalance[msg.sender] = balance - toWithdraw;

        token.safeTransfer(msg.sender, toWithdraw);

        emit Withdrawn(msg.sender, toWithdraw);
    }

    /**
     * @notice Owner can toggle NFT badge minting on/off.
     */
    function setBadgesEnabled(bool enabled) external onlyOwner {
        badgesEnabled = enabled;
        emit BadgesEnabled(enabled);
    }

    // ----------------- INTERNAL NFT LOGIC -----------------

    /**
     * @dev Internal function to mint a patron badge NFT to a supporter.
     *      The badge is associated with a specific athlete via event + mapping.
     */
    function _mintBadge(address supporter, address athlete) internal {
        uint256 tokenId = _nextTokenId;
        _nextTokenId++;

        hasBadge[athlete][supporter] = true;

        _safeMint(supporter, tokenId);

        emit BadgeMinted(tokenId, supporter, athlete);
    }

    /**
     * @dev (Optional) You can override tokenURI() later to reflect athlete/supporter pairing
     *      using off-chain metadata if you want pretty badges.
     */

    // ----------------- VIEW HELPERS -----------------

    /**
     * @notice Returns supporter info for a given (athlete, supporter) pair.
     */
    function getSupportRecord(
        address athlete,
        address supporter
    ) external view returns (SupportRecord memory) {
        return supportInfo[athlete][supporter];
    }
}

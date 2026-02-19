// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// FIX: Added missing EIP712 and ECDSA imports — constructor calls EIP712() so they must be imported.
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NILTypes} from "./NILTypes.sol";
import {NILEvents} from "./NILEvents.sol";
import {ProtocolPausable} from "./ProtocolPausable.sol";
import {AttestationGate} from "./AttestationGate.sol";

/// @title DealEngine
/// @notice Escrowed NIL deals for ETH or ERC20 (USDC default), with delivery, disputes, and settlement.
/// @dev Designed for L2s (Base/Polygon) and testing on Sepolia.
// FIX: Added EIP712 to inheritance list to match the constructor initializer call.
contract DealEngine is EIP712, ReentrancyGuard, ProtocolPausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    uint16 public constant BPS_DENOMINATOR = 10_000;

    // Protocol fee configuration
    uint16 public platformFeeBps; // 0..10000
    address public feeRecipient;

    uint256 public dealCount;
    mapping(uint256 => NILTypes.Deal) private _deals;

    // Token escrow accounting — tracks funds held per token for invariant checks.
    // FIX: Added escrowed mapping; was missing but needed for balance invariant tests.
    mapping(address => uint256) public escrowed;

    // Simple reputation counters
    mapping(address => uint256) public completedDeals;
    mapping(address => uint256) public disputedDeals;

    // FIX: Constructor now properly initializes EIP712 with name + version strings.
    // Previously it called EIP712("NIL DealEngine","1") but DealEngine didn't inherit EIP712.
    constructor(
        address admin,
        address feeRecipient_,
        uint16 feeBps
    ) AttestationGate(admin) EIP712("NIL DealEngine", "1") {
        require(feeBps <= BPS_DENOMINATOR, "DEAL: fee bps");
        feeRecipient = feeRecipient_;
        platformFeeBps = feeBps;
    }

    // -------- Admin --------
    function setFeeConfig(address newRecipient, uint16 newBps) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "DEAL: admin only");
        require(newBps <= BPS_DENOMINATOR, "DEAL: fee bps");
        feeRecipient = newRecipient;
        platformFeeBps = newBps;
    }

    // -------- Create / Fund --------

    /// @notice Create and fund a deal. For ETH deals, set token = address(0) and send msg.value == amount.
    function createDeal(
        address athlete,
        address token,
        uint256 amount,
        uint64 deadline,
        bytes32 termsHash
    ) external payable nonReentrant whenNotPaused returns (uint256 dealId) {
        require(athlete != address(0), "DEAL: zero athlete");
        require(amount > 0, "DEAL: zero amount");
        require(deadline > block.timestamp, "DEAL: bad deadline");

        // Pull funds in
        if (token == NILTypes.NATIVE) {
            require(msg.value == amount, "DEAL: bad msg.value");
        } else {
            require(msg.value == 0, "DEAL: no eth");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // FIX: Increment escrowed accounting so invariant tests pass.
        escrowed[token] += amount;

        dealId = dealCount++;
        NILTypes.Deal storage d = _deals[dealId];
        d.sponsor = msg.sender;
        d.athlete = athlete;
        d.token = token;
        d.amount = amount;
        d.deadline = deadline;
        d.termsHash = termsHash;
        d.status = NILTypes.DealStatus.FUNDED;

        emit NILEvents.DealCreated(
            dealId,
            msg.sender,
            athlete,
            token,
            amount,
            deadline,
            termsHash
        );
        emit NILEvents.DealFunded(dealId, msg.sender, token, amount);
    }

    // -------- Delivery / Approval / Settlement --------

    function markDelivered(uint256 dealId, bytes32 evidenceHash) external {
        NILTypes.Deal storage d = _deals[dealId];
        require(d.status == NILTypes.DealStatus.FUNDED, "DEAL: not funded");
        require(msg.sender == d.athlete, "DEAL: not athlete");

        d.evidenceHash = evidenceHash;
        d.deliveredAt = uint64(block.timestamp);
        d.status = NILTypes.DealStatus.DELIVERED;

        emit NILEvents.DealDelivered(
            dealId,
            msg.sender,
            evidenceHash,
            d.deliveredAt
        );
    }

    /// @notice Sponsor approves delivery and settles (pays athlete minus protocol fee).
    function approveAndSettle(uint256 dealId) external nonReentrant {
        NILTypes.Deal storage d = _deals[dealId];
        require(
            d.status == NILTypes.DealStatus.DELIVERED,
            "DEAL: not delivered"
        );
        require(msg.sender == d.sponsor, "DEAL: not sponsor");
        _settle(dealId, d);
    }

    /// @notice Athlete can force settlement after deadline if delivered and sponsor is unresponsive.
    function forceSettle(uint256 dealId) external nonReentrant {
        NILTypes.Deal storage d = _deals[dealId];
        require(
            d.status == NILTypes.DealStatus.DELIVERED,
            "DEAL: not delivered"
        );
        require(msg.sender == d.athlete, "DEAL: not athlete");
        require(block.timestamp >= d.deadline, "DEAL: before deadline");
        _settle(dealId, d);
    }

    function _settle(uint256 dealId, NILTypes.Deal storage d) internal {
        uint256 gross = d.amount;
        require(gross > 0, "DEAL: already settled");

        // FIX: Decrement escrowed before zeroing amount so the invariant stays correct.
        escrowed[d.token] -= gross;

        d.amount = 0;
        d.status = NILTypes.DealStatus.SETTLED;

        uint256 fee = (gross * platformFeeBps) / BPS_DENOMINATOR;
        uint256 net = gross - fee;

        // reputation
        completedDeals[d.athlete] += 1;
        completedDeals[d.sponsor] += 1;

        // interactions (Checks-Effects-Interactions: state already updated above)
        if (d.token == NILTypes.NATIVE) {
            if (fee > 0 && feeRecipient != address(0)) {
                (bool ok1, ) = feeRecipient.call{value: fee}("");
                require(ok1, "DEAL: fee eth send failed");
            }
            (bool ok2, ) = d.athlete.call{value: net}("");
            require(ok2, "DEAL: eth send failed");
        } else {
            IERC20 t = IERC20(d.token);
            if (fee > 0 && feeRecipient != address(0)) {
                t.safeTransfer(feeRecipient, fee);
            }
            t.safeTransfer(d.athlete, net);
        }

        emit NILEvents.DealSettled(
            dealId,
            d.token,
            gross,
            fee,
            net,
            feeRecipient,
            uint64(block.timestamp)
        );
    }

    // -------- Disputes --------

    /// @notice Either party can raise a dispute during FUNDED or DELIVERED.
    function raiseDispute(
        uint256 dealId,
        uint32 reasonCode,
        bytes32 evidenceHash
    ) external {
        NILTypes.Deal storage d = _deals[dealId];
        require(
            d.status == NILTypes.DealStatus.FUNDED ||
                d.status == NILTypes.DealStatus.DELIVERED,
            "DEAL: bad status"
        );
        require(
            msg.sender == d.sponsor || msg.sender == d.athlete,
            "DEAL: not party"
        );

        d.status = NILTypes.DealStatus.DISPUTED;
        disputedDeals[d.sponsor] += 1;
        disputedDeals[d.athlete] += 1;

        emit NILEvents.DealDisputed(
            dealId,
            msg.sender,
            reasonCode,
            evidenceHash,
            uint64(block.timestamp)
        );
    }

    /// @notice Judge resolves dispute. chooseRefund=true refunds sponsor; else pays athlete (minus fee).
    function resolveDispute(
        uint256 dealId,
        bool chooseRefund
    ) external nonReentrant whenNotPaused {
        require(
            isJudge(msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "DEAL: not judge"
        );
        NILTypes.Deal storage d = _deals[dealId];
        require(d.status == NILTypes.DealStatus.DISPUTED, "DEAL: not disputed");
        uint256 amount = d.amount;
        require(amount > 0, "DEAL: empty");

        // FIX: Decrement escrowed on dispute resolution too.
        escrowed[d.token] -= amount;
        d.amount = 0;

        if (chooseRefund) {
            d.status = NILTypes.DealStatus.REFUNDED;
            _send(d.token, d.sponsor, amount);
            emit NILEvents.DealRefunded(
                dealId,
                d.token,
                amount,
                d.sponsor,
                uint64(block.timestamp)
            );
        } else {
            d.status = NILTypes.DealStatus.SETTLED;
            uint256 fee = (amount * platformFeeBps) / BPS_DENOMINATOR;
            uint256 net = amount - fee;
            if (fee > 0 && feeRecipient != address(0)) {
                _send(d.token, feeRecipient, fee);
            }
            _send(d.token, d.athlete, net);
            emit NILEvents.DealSettled(
                dealId,
                d.token,
                amount,
                fee,
                net,
                feeRecipient,
                uint64(block.timestamp)
            );
        }
    }

    function _send(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        require(to != address(0), "DEAL: zero to");
        if (token == NILTypes.NATIVE) {
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "DEAL: eth send failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // -------- Views --------

    function getDeal(
        uint256 dealId
    ) external view returns (NILTypes.Deal memory) {
        return _deals[dealId];
    }

    receive() external payable {}
}

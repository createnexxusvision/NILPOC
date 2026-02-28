// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {NILEvents} from "../core/NILEvents.sol";

/// @title ReceiptNFT
/// @notice Optional NFT receipts for marketplace orders / NIL payments.
/// @dev Minting is permissioned (marketplace router) to prevent data pollution.
contract ReceiptNFT is ERC721URIStorage, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    struct Receipt {
        bytes32 orderHash;
        address buyer;
        address seller;
        address token; // address(0) == ETH
        uint256 price;
        uint256 platformFee;
        uint64 timestamp;
    }

    uint256 public nextTokenId;
    mapping(uint256 => Receipt) public receipts;

    constructor(address admin) ERC721("NIL Receipt", "NILR") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function mintReceipt(
        bytes32 orderHash,
        address buyer,
        address seller,
        address token,
        uint256 price,
        uint256 platformFee,
        string calldata tokenURI_
    ) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        require(buyer != address(0) && seller != address(0), "RECEIPT: zero addr");
        tokenId = ++nextTokenId;
        _safeMint(buyer, tokenId);
        _setTokenURI(tokenId, tokenURI_);

        receipts[tokenId] = Receipt({
            orderHash: orderHash,
            buyer: buyer,
            seller: seller,
            token: token,
            price: price,
            platformFee: platformFee,
            timestamp: uint64(block.timestamp)
        });

        emit NILEvents.ReceiptMinted(tokenId, orderHash, buyer, seller, token, price, platformFee, tokenURI_);
    }

    // FIX: ERC721URIStorage and AccessControl both define supportsInterface().
    // Solidity requires an explicit override when two bases conflict.
    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

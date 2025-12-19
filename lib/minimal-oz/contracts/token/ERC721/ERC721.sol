// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract ERC721 {
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    // Minimal stub for `_safeMint` used by PatronStream tests
    function _safeMint(address to, uint256 tokenId) internal virtual {
        // minimal: no-op for tests in this workspace
    }
}

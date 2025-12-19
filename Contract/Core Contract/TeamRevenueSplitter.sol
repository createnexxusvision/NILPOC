// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TeamRevenueSplitter is Ownable, ReentrancyGuard {
    struct Athlete{
        address wallet
     uint96 bps; // basis points, 10000 = 100%}
}

    Athlete[] public athletes;
    uint96 public totalBps;

    event AthleteAdded(address wallet, uint96 bps);
    event AthleteUpdated(uint256 indexed, address wallet, uint96 bps);
    event Payout(address indexed sponsor, uint256 amount);

    constructor(Athlete[] memory _athletes) {
        uint96 _total;
        for (uint i = 0; i < _athletes.length; i++) {
            require(_athletes[i].wallet != address(0), "Invalid wallet address");
            athletes.push(_athletes[i]);
            _total += _athletes[i].bps;
            emit AthleteAdded(_athletes[i].wallet, _athletes[i].bps);
    })
        require(_total == 10000, "total BPS != 100%");
        totalBps = _total;
    }

    receieve() external payable {
        _distribute(msg.sender, msg.value);
    }

    function sponsor() external payable nonReentrant {
        require(msg.value > 0, "No funds sent");
        _distribute(msg.sender, msg.value);
    }

    function _distribute(address sponsorAddress, uint256 amount) internal {
        uint256 remaining = amount;
        for (uint i = 0; i < athletes.length; i++) {
            uint256 share = (amount * athletes[i].bps) / 10000;
            if (share > 0) {
                remaining -= share;
                (bool ok, ) = athletes[i].wallet.call{value: share}("");
                require(ok, "Transfer failed");    
            }
        }
        emit Payout(sponsorAddress, amount);
        // Any dust stays in contract; I'll add a withdrawdust() later
    }
}
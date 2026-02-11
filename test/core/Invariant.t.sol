// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";

import {PayoutRouter} from "../../src/core/PayoutRouter.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {NILTypes} from "../../src/core/NILTypes.sol";

contract PayoutHandler is Test {
    PayoutRouter public router;
    MockUSDC public usdc;

    uint256 public lastSplitId;

    constructor(PayoutRouter _router, MockUSDC _usdc) {
        router = _router;
        usdc = _usdc;
    }

    function makeSplit(address a, address b) public {
        NILTypes.SplitRecipient[] memory r = new NILTypes.SplitRecipient[](2);
        r[0] = NILTypes.SplitRecipient({recipient: a, bps: 5000});
        r[1] = NILTypes.SplitRecipient({recipient: b, bps: 5000});
        // router requires operator/admin; in tests, this handler is given operator role by admin.
        lastSplitId = router.defineSplit(r);
    }

    function payETH(bytes32 ref, uint256 amount) public {
        if (router.splitCount() == 0) return;
        amount = bound(amount, 1e12, 1 ether);
        vm.deal(address(this), amount);
        router.payout{value: amount}(ref, NILTypes.NATIVE, amount, lastSplitId);
    }

    function payUSDC(bytes32 ref, uint256 amount) public {
        if (router.splitCount() == 0) return;
        amount = bound(amount, 1e3, 10_000 * 1e6); // up to 10k USDC
        usdc.mint(address(this), amount);
        usdc.approve(address(router), amount);
        router.payout(ref, address(usdc), amount, lastSplitId);
    }
}

contract Invariant_PayoutRouter is StdInvariant, Test {
    PayoutRouter public router;
    MockUSDC public usdc;
    PayoutHandler public handler;

    function setUp() public {
        router = new PayoutRouter(address(this));
        usdc = new MockUSDC();
        handler = new PayoutHandler(router, usdc);

        // Give handler operator role so it can define splits.
        router.grantRole(router.OPERATOR_ROLE(), address(handler));

        targetContract(address(handler));
    }

    /// Invariant: router should not retain ETH (it is a pure router).
    function invariant_routerEthBalanceIsZero() public {
        assertEq(address(router).balance, 0);
    }

    /// Invariant: router should not retain USDC after payouts (it is a pure router).
    function invariant_routerUsdcBalanceIsZero() public {
        assertEq(usdc.balanceOf(address(router)), 0);
    }
}

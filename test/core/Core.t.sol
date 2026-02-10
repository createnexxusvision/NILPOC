// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {DealEngine} from "../../src/core/DealEngine.sol";
import {DeferredVault} from "../../src/core/DeferredVault.sol";
import {PayoutRouter} from "../../src/core/PayoutRouter.sol";
import {NILTypes} from "../../src/core/NILTypes.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

contract CoreTest is Test {
    DealEngine engine;
    DeferredVault vault;
    PayoutRouter router;
    MockUSDC usdc;

    address admin = address(0xA11CE);
    address sponsor = address(0xB0B);
    address athlete = address(0xCAFE);
    address judge = address(0xD00D);
    address feeRecipient = address(0xFEE);

    function setUp() public {
        vm.startPrank(admin);
        engine = new DealEngine(admin, feeRecipient, 200); // 2%
        vault = new DeferredVault(admin, true);
        router = new PayoutRouter(admin);
        usdc = new MockUSDC();
        // roles
        engine.grantRole(engine.JUDGE_ROLE(), judge);
        vault.grantRole(vault.ORACLE_ROLE(), admin);
        vm.stopPrank();

        // mint sponsor USDC
        usdc.mint(sponsor, 1_000_000e6);
        vm.deal(sponsor, 10 ether);
        vm.deal(athlete, 1 ether);
    }

    function testDealEthHappyPath() public {
        bytes32 terms = keccak256("terms");
        vm.prank(sponsor);
        uint256 id = engine.createDeal{value: 1 ether}(athlete, NILTypes.NATIVE, 1 ether, uint64(block.timestamp + 1 days), terms);

        vm.prank(athlete);
        engine.markDelivered(id, keccak256("evidence"));

        uint256 feeBefore = feeRecipient.balance;
        uint256 athleteBefore = athlete.balance;

        vm.prank(sponsor);
        engine.approveAndSettle(id);

        // 2% fee
        assertEq(feeRecipient.balance - feeBefore, 0.02 ether);
        assertEq(athlete.balance - athleteBefore, 0.98 ether);
    }

    function testDealUsdcDisputeRefundByJudge() public {
        bytes32 terms = keccak256("terms");
        uint256 amount = 100e6;
        vm.startPrank(sponsor);
        usdc.approve(address(engine), amount);
        uint256 id = engine.createDeal(athlete, address(usdc), amount, uint64(block.timestamp + 1 days), terms);
        vm.stopPrank();

        vm.prank(sponsor);
        engine.raiseDispute(id, 1, bytes32(0));

        uint256 sponsorBefore = usdc.balanceOf(sponsor);
        vm.prank(judge);
        engine.resolveDispute(id, true);
        assertEq(usdc.balanceOf(sponsor) - sponsorBefore, amount);
    }

    function testVaultAttestedWithdraw() public {
        bytes32 terms = keccak256("terms");
        uint256 amt = 50e6;
        vm.startPrank(sponsor);
        usdc.approve(address(vault), amt);
        uint256 gid = vault.createGrant(athlete, address(usdc), amt, uint64(block.timestamp + 7 days), terms);
        vm.stopPrank();

        vm.prank(admin);
        vault.attestGrant(gid, keccak256("ok"));

        vm.warp(block.timestamp + 8 days);
        uint256 balBefore = usdc.balanceOf(athlete);
        vm.prank(athlete);
        vault.withdraw(gid);
        assertEq(usdc.balanceOf(athlete) - balBefore, amt);
    }

    function testRouterSplitUsdc() public {
        // define split 50/50
        NILTypes.SplitRecipient[] memory rec = new NILTypes.SplitRecipient[](2);
        rec[0] = NILTypes.SplitRecipient({recipient: athlete, bps: 5000});
        rec[1] = NILTypes.SplitRecipient({recipient: feeRecipient, bps: 5000});
        vm.prank(admin);
        uint256 splitId = router.defineSplit(rec);

        uint256 amt = 10e6;
        vm.startPrank(sponsor);
        usdc.approve(address(router), amt);
        uint256 athleteBefore = usdc.balanceOf(athlete);
        uint256 feeBefore = usdc.balanceOf(feeRecipient);
        router.payout(bytes32("order"), address(usdc), amt, splitId);
        vm.stopPrank();

        assertEq(usdc.balanceOf(athlete) - athleteBefore, 5e6);
        assertEq(usdc.balanceOf(feeRecipient) - feeBefore, 5e6);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Swarmpeg} from "src/Swarmpeg.sol";

/// @dev Complements the deployment/basic ERC-20 tests with boundaries and approval lifecycle properties.
/// forge-config: default.fuzz.runs = 1024
contract SwarmpegAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Swarmpeg internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        token = new Swarmpeg();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_OneWeiTransferRoundTrip() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneAllowanceIsFinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UnlimitedApprovalCanBeReducedThenRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 3));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 3, 4));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 4);
        assertEq(token.allowance(address(this), spender), 3);
        assertEq(token.balanceOf(alice), 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 1);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FundedOriginCannotAuthorizeCallerTransfersOrApprovals() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice, address(this));
        token.transfer(bob, 1);

        vm.prank(alice, address(this));
        assertTrue(token.approve(spender, 7));
        assertEq(token.allowance(alice, spender), 7);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromUsesCallerAllowanceRatherThanOrigin() public {
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob, spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(spender, bob);
        assertTrue(token.transferFrom(address(this), alice, 100));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransfersStillRequireSufficientBalance() public {
        assertTrue(token.transfer(alice, 5));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5, 6));
        vm.prank(alice);
        token.transfer(alice, 6);
        assertEq(token.balanceOf(alice), 5);

        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5, 6));
        vm.prank(spender);
        token.transferFrom(alice, alice, 6);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 5);
        assertEq(token.balanceOf(address(this)), SUPPLY - 5);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_WholeSupplySentToTokenRemainsInSupply() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferToZeroCannotConsumeAnyKindOfAllowance() public {
        uint256[4] memory approvals = [uint256(0), 1, type(uint256).max - 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), spender), approvals[i]);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_ZeroSpenderRejectedForZeroAndMaximumApproval() public {
        uint256[2] memory approvals = [uint256(0), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), approvals[i]);
            assertEq(token.allowance(address(this), address(0)), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testFuzz_SplitSpendsCannotReuseExhaustedAllowance(uint256 approvedSeed, uint256 splitSeed) public {
        uint256 approved = bound(approvedSeed, 1, SUPPLY);
        uint256 first = bound(splitSeed, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.allowance(address(this), spender), approved - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, approved - first));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), spender, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - approved);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), approved - first);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_CompetingSpendersShareBalanceButNotAllowance(uint256 firstSeed) public {
        uint256 first = bound(firstSeed, 1, SUPPLY - 1);
        uint256 remaining = SUPPLY - first;
        assertTrue(token.approve(spender, SUPPLY));
        assertTrue(token.approve(bob, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.allowance(address(this), spender), remaining);
        assertEq(token.allowance(address(this), bob), SUPPLY);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), remaining, remaining + 1
            )
        );
        vm.prank(bob);
        token.transferFrom(address(this), bob, remaining + 1);
        assertEq(token.allowance(address(this), bob), SUPPLY);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), bob, remaining));
        assertEq(token.allowance(address(this), bob), first);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), spender, 1);
        assertEq(token.allowance(address(this), spender), remaining);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), remaining);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendCanBeRetriedAfterFunding(uint256 balanceSeed, uint256 shortfallSeed, bool unlimited)
        public
    {
        uint256 balance = bound(balanceSeed, 0, SUPPLY - 1);
        uint256 shortfall = bound(shortfallSeed, 1, SUPPLY - balance);
        uint256 amount = balance + shortfall;
        uint256 approved = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        assertTrue(token.transfer(alice, shortfall));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevocationSurvivesBalanceMovingOutAndBack(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        vm.startPrank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.transfer(bob, amount));
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount));
        vm.prank(spender);
        token.transferFrom(alice, spender, amount);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalsDoNotFollowTokensToAnotherHolder(uint256 amountSeed, uint256 approvalSeed) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        uint256 approved = bound(approvalSeed, 1, type(uint256).max);
        assertTrue(token.transfer(alice, amount));
        vm.startPrank(alice);
        assertTrue(token.approve(spender, approved));
        assertTrue(token.transfer(bob, amount));
        vm.stopPrank();
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.allowance(bob, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(bob, spender, 1);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(spender), 0);

        // Funding the original owner makes its existing approval usable again, without a new approve call.
        vm.prank(bob);
        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 1));
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - 1);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount - 1);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}

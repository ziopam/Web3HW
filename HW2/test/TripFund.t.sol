pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TripFund} from "../src/TripFund.sol";
import {MockToken} from "../src/MockToken.sol";

contract TripFundTest is Test {
    MockToken internal token;
    TripFund internal fund;
    address internal organizer = makeAddr("organizer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");
    uint256 internal constant GOAL = 100 ether;
    uint256 internal constant INITIAL = 1_000 ether;
    uint256 internal deadline;

    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    function setUp() public {
        vm.warp(1_000);
        deadline = block.timestamp + 7 days;
        token = new MockToken(10_000 ether);
        fund = new TripFund(token, organizer, GOAL, deadline);
        assertTrue(token.transfer(alice, INITIAL));
        assertTrue(token.transfer(bob, INITIAL));
        vm.prank(alice);
        token.approve(address(fund), type(uint256).max);
        vm.prank(bob);
        token.approve(address(fund), type(uint256).max);
    }

    function _contribute(address who, uint256 amount) internal {
        vm.prank(who);
        fund.contribute(amount);
    }

    function _withdraw() internal {
        vm.prank(organizer);
        fund.withdraw();
    }

    function _refund(address who) internal {
        vm.prank(who);
        fund.refund();
    }

    function _assertAccounting(uint256 a, uint256 b, uint256 raised, uint256 balance) internal view {
        assertEq(fund.contributions(alice), a);
        assertEq(fund.contributions(bob), b);
        assertEq(fund.totalRaised(), raised);
        assertEq(token.balanceOf(address(fund)), balance);
    }

    function testConstructorStoresParameters() public view {
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
        assertFalse(fund.withdrawn());
        _assertAccounting(0, 0, 0, 0);
    }

    function testConstructorRejectsZeroToken() public {
        vm.expectRevert(TripFund.ZeroAddress.selector);
        new TripFund(IERC20(address(0)), organizer, GOAL, deadline);
    }

    function testConstructorRejectsZeroOrganizer() public {
        vm.expectRevert(TripFund.ZeroAddress.selector);
        new TripFund(token, address(0), GOAL, deadline);
    }

    function testConstructorRejectsZeroGoal() public {
        vm.expectRevert(TripFund.ZeroGoal.selector);
        new TripFund(token, organizer, 0, deadline);
    }

    function testConstructorRejectsCurrentAndPastDeadline() public {
        vm.expectRevert(TripFund.InvalidDeadline.selector);
        new TripFund(token, organizer, GOAL, block.timestamp);
        vm.expectRevert(TripFund.InvalidDeadline.selector);
        new TripFund(token, organizer, GOAL, block.timestamp - 1);
    }

    function testTwoContributorsAndRepeatedContributionsEmitEvents() public {
        vm.expectEmit(true, false, false, true, address(fund));
        emit Contributed(alice, 20 ether);
        _contribute(alice, 20 ether);
        _contribute(bob, 30 ether);
        _contribute(alice, 15 ether);
        _assertAccounting(35 ether, 30 ether, 65 ether, 65 ether);
        assertEq(token.balanceOf(alice), INITIAL - 35 ether);
        assertEq(token.balanceOf(bob), INITIAL - 30 ether);
    }

    function testZeroContributionRevertsWithoutChanges() public {
        _contribute(alice, 10 ether);
        vm.expectRevert(TripFund.ZeroAmount.selector);
        _contribute(alice, 0);
        _assertAccounting(10 ether, 0, 10 ether, 10 ether);
        assertEq(token.balanceOf(alice), INITIAL - 10 ether);
        assertEq(token.balanceOf(bob), INITIAL);
        assertEq(token.allowance(alice, address(fund)), type(uint256).max);
    }

    function testInsufficientBalanceRollsBackExistingAccountingAndAllowance() public {
        _contribute(alice, 10 ether);
        uint256 remaining = INITIAL - 10 ether;
        uint256 amount = remaining + 1;
        vm.prank(alice);
        token.approve(address(fund), amount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, remaining, amount)
        );
        _contribute(alice, amount);
        _assertAccounting(10 ether, 0, 10 ether, 10 ether);
        assertEq(token.balanceOf(alice), remaining);
        assertEq(token.balanceOf(bob), INITIAL);
        assertEq(token.allowance(alice, address(fund)), amount);
    }

    function testInsufficientAllowanceRollsBackExistingAccounting() public {
        _contribute(alice, 10 ether);
        vm.prank(alice);
        token.approve(address(fund), 4 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), 4 ether, 5 ether
            )
        );
        _contribute(alice, 5 ether);
        _assertAccounting(10 ether, 0, 10 ether, 10 ether);
        assertEq(token.balanceOf(alice), INITIAL - 10 ether);
        assertEq(token.balanceOf(bob), INITIAL);
        assertEq(token.allowance(alice, address(fund)), 4 ether);
    }

    function testContributionOneSecondBeforeDeadlineAndRejectionAtDeadline() public {
        vm.warp(deadline - 1);
        _contribute(alice, 10 ether);
        vm.warp(deadline);
        vm.expectRevert(TripFund.FundingClosed.selector);
        _contribute(bob, 20 ether);
        _assertAccounting(10 ether, 0, 10 ether, 10 ether);
        assertEq(token.balanceOf(bob), INITIAL);
    }

    function testContributionAfterDeadlineRejected() public {
        vm.warp(deadline + 1);
        vm.expectRevert(TripFund.FundingClosed.selector);
        _contribute(alice, 1);
        _assertAccounting(0, 0, 0, 0);
        assertEq(token.balanceOf(alice), INITIAL);
    }

    function testPayoutsBeforeDeadlineRejectedBelowGoal() public {
        _contribute(alice, 10 ether);
        vm.warp(deadline - 1);
        vm.expectRevert(TripFund.FundingStillOpen.selector);
        _withdraw();
        vm.expectRevert(TripFund.FundingStillOpen.selector);
        _refund(alice);
        _assertAccounting(10 ether, 0, 10 ether, 10 ether);
        assertFalse(fund.withdrawn());
    }

    function testPayoutsBeforeDeadlineRejectedEvenAtGoal() public {
        _contribute(alice, GOAL);
        vm.warp(deadline - 1);
        vm.expectRevert(TripFund.FundingStillOpen.selector);
        _withdraw();
        vm.expectRevert(TripFund.FundingStillOpen.selector);
        _refund(alice);
        _assertAccounting(GOAL, 0, GOAL, GOAL);
        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(organizer), 0);
    }

    function testExactGoalWithdrawalPermissionsEventAndNoRepeat() public {
        _contribute(alice, 40 ether);
        _contribute(bob, 60 ether);
        vm.warp(deadline);
        vm.prank(stranger);
        vm.expectRevert(TripFund.NotOrganizer.selector);
        fund.withdraw();
        vm.expectRevert(TripFund.GoalReached.selector);
        _refund(alice);
        vm.expectEmit(true, false, false, true, address(fund));
        emit Withdrawn(organizer, GOAL);
        _withdraw();
        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(alice), INITIAL - 40 ether);
        assertEq(token.balanceOf(bob), INITIAL - 60 ether);
        assertTrue(fund.withdrawn());
        _assertAccounting(40 ether, 60 ether, GOAL, 0);
        vm.expectRevert(TripFund.AlreadyWithdrawn.selector);
        _withdraw();
        vm.expectRevert(TripFund.GoalReached.selector);
        _refund(bob);
        assertEq(token.balanceOf(organizer), GOAL);
    }

    function testOverGoalWithdrawsEntireAccountedSum() public {
        _contribute(alice, GOAL);
        _contribute(bob, 25 ether);
        vm.warp(deadline + 1);
        _withdraw();
        assertEq(token.balanceOf(organizer), 125 ether);
        _assertAccounting(GOAL, 25 ether, 125 ether, 0);
    }

    function testUnsuccessfulFundIndependentRefundsEventAndNoRepeat() public {
        _contribute(alice, 10 ether);
        _contribute(alice, 20 ether);
        _contribute(bob, 25 ether);
        vm.warp(deadline);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        _withdraw();
        vm.expectRevert(TripFund.NoContribution.selector);
        _refund(stranger);
        vm.expectEmit(true, false, false, true, address(fund));
        emit Refunded(alice, 30 ether);
        _refund(alice);
        _assertAccounting(0, 25 ether, 55 ether, 25 ether);
        assertEq(token.balanceOf(alice), INITIAL);
        assertEq(token.balanceOf(bob), INITIAL - 25 ether);
        vm.expectRevert(TripFund.NoContribution.selector);
        _refund(alice);
        _refund(bob);
        _assertAccounting(0, 0, 55 ether, 0);
        assertEq(token.balanceOf(alice), INITIAL);
        assertEq(token.balanceOf(bob), INITIAL);
        assertEq(token.balanceOf(organizer), 0);
        assertFalse(fund.withdrawn());
    }

    function testEmptyFundCannotWithdrawOrRefund() public {
        vm.warp(deadline);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        _withdraw();
        vm.expectRevert(TripFund.NoContribution.selector);
        _refund(alice);
        _assertAccounting(0, 0, 0, 0);
    }

    function testDirectTransferRemainsAfterSuccessfulWithdrawal() public {
        assertTrue(token.transfer(address(fund), 17 ether));
        _assertAccounting(0, 0, 0, 17 ether);
        assertEq(fund.contributions(address(this)), 0);
        _contribute(alice, GOAL);
        vm.warp(deadline);
        _withdraw();
        _assertAccounting(GOAL, 0, GOAL, 17 ether);
        assertEq(token.balanceOf(organizer), GOAL);
    }

    function testDirectTransferDoesNotReachGoalAndRemainsAfterRefunds() public {
        _contribute(alice, 30 ether);
        _contribute(bob, 20 ether);
        assertTrue(token.transfer(address(fund), 100 ether));
        _assertAccounting(30 ether, 20 ether, 50 ether, 150 ether);
        vm.warp(deadline);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        _withdraw();
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();
        _refund(bob);
        _refund(alice);
        _assertAccounting(0, 0, 50 ether, 100 ether);
        assertEq(token.balanceOf(alice), INITIAL);
        assertEq(token.balanceOf(bob), INITIAL);
    }

    function testFuzzRepeatedContributionsAndIndependentRefunds(uint256 a, uint256 b, uint256 repeat)
        public
    {
        a = bound(a, 1, GOAL / 4);
        b = bound(b, 1, GOAL / 4);
        repeat = bound(repeat, 1, GOAL / 4);
        uint256 total = a + b + repeat;
        _contribute(alice, a);
        _contribute(bob, b);
        _contribute(alice, repeat);
        _assertAccounting(a + repeat, b, total, total);
        vm.warp(deadline);
        _refund(bob);
        _assertAccounting(a + repeat, 0, total, a + repeat);
        assertEq(token.balanceOf(bob), INITIAL);
        _refund(alice);
        _assertAccounting(0, 0, total, 0);
        assertEq(token.balanceOf(alice), INITIAL);
    }

    function testFuzzSuccessfulWithdrawalExcludesUnaccountedTokens(uint256 a, uint256 b, uint256 donation)
        public
    {
        a = bound(a, GOAL, INITIAL);
        b = bound(b, 1, INITIAL);
        donation = bound(donation, 1, 100 ether);
        assertTrue(token.transfer(address(fund), donation));
        _contribute(alice, a);
        _contribute(bob, b);
        vm.warp(deadline);
        _withdraw();
        _assertAccounting(a, b, a + b, donation);
        assertEq(token.balanceOf(organizer), a + b);
        assertEq(token.balanceOf(alice), INITIAL - a);
        assertEq(token.balanceOf(bob), INITIAL - b);
    }
}

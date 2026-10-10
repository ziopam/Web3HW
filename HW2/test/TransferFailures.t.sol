pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TripFund} from "../src/TripFund.sol";

contract FalseReturningToken is ERC20 {
    bool public fail;

    constructor() ERC20("Failure token", "FAIL") {
        _mint(msg.sender, 1_000 ether);
    }

    function setFail(bool value) external {
        fail = value;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool success = super.transfer(to, amount);
        return success && !fail;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool success = super.transferFrom(from, to, amount);
        return success && !fail;
    }
}

contract TransferFailuresTest is Test {
    FalseReturningToken token;
    TripFund fund;
    address organizer = address(0xBEEF);
    uint256 deadline;

    function setUp() public {
        vm.warp(1_000);
        deadline = block.timestamp + 100;
        token = new FalseReturningToken();
        fund = new TripFund(token, organizer, 100 ether, deadline);
        token.approve(address(fund), 1_000 ether);
    }

    function expectTransferFailure() internal {
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
    }

    function testTransferErrorContributionRollsBackAccountingBalancesAndAllowance() public {
        fund.contribute(10 ether);
        token.setFail(true);
        expectTransferFailure();
        fund.contribute(20 ether);
        assertEq(fund.totalRaised(), 10 ether);
        assertEq(fund.contributions(address(this)), 10 ether);
        assertEq(token.balanceOf(address(this)), 990 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
        assertEq(token.allowance(address(this), address(fund)), 990 ether);
    }

    function testTransferErrorWithdrawRestoresFlagAndAllowsRetry() public {
        fund.contribute(100 ether);
        vm.warp(deadline);
        token.setFail(true);
        expectTransferFailure();
        vm.prank(organizer);
        fund.withdraw();
        assertFalse(fund.withdrawn());
        assertEq(fund.totalRaised(), 100 ether);
        assertEq(fund.contributions(address(this)), 100 ether);
        assertEq(token.balanceOf(address(fund)), 100 ether);
        assertEq(token.balanceOf(organizer), 0);
        token.setFail(false);
        vm.prank(organizer);
        fund.withdraw();
        assertTrue(fund.withdrawn());
        assertEq(token.balanceOf(organizer), 100 ether);
    }

    function testTransferErrorRefundRestoresContributionAndAllowsRetry() public {
        fund.contribute(10 ether);
        vm.warp(deadline);
        token.setFail(true);
        expectTransferFailure();
        fund.refund();
        assertEq(fund.contributions(address(this)), 10 ether);
        assertEq(fund.totalRaised(), 10 ether);
        assertEq(token.balanceOf(address(this)), 990 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
        token.setFail(false);
        fund.refund();
        assertEq(fund.contributions(address(this)), 0);
        assertEq(fund.totalRaised(), 10 ether);
        assertEq(token.balanceOf(address(this)), 1_000 ether);
        assertEq(token.balanceOf(address(fund)), 0);
    }
}

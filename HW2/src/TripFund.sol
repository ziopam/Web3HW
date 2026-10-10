pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TripFund {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable organizer;
    uint256 public immutable goal;
    uint256 public immutable deadline;

    mapping(address => uint256) public contributions;
    uint256 public totalRaised;
    bool public withdrawn;

    error ZeroAddress();
    error ZeroGoal();
    error InvalidDeadline();
    error ZeroAmount();
    error FundingClosed();
    error FundingStillOpen();
    error NotOrganizer();
    error GoalNotReached();
    error GoalReached();
    error AlreadyWithdrawn();
    error NoContribution();

    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    constructor(IERC20 token_, address organizer_, uint256 goal_, uint256 deadline_) {
        if (address(token_) == address(0) || organizer_ == address(0)) revert ZeroAddress();
        if (goal_ == 0) revert ZeroGoal();
        if (deadline_ <= block.timestamp) revert InvalidDeadline();
        token = token_;
        organizer = organizer_;
        goal = goal_;
        deadline = deadline_;
    }

    function contribute(uint256 amount) external {
        if (block.timestamp >= deadline) revert FundingClosed();
        if (amount == 0) revert ZeroAmount();

        contributions[msg.sender] += amount;
        totalRaised += amount;
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Contributed(msg.sender, amount);
    }

    function withdraw() external {
        if (block.timestamp < deadline) revert FundingStillOpen();
        if (msg.sender != organizer) revert NotOrganizer();
        if (totalRaised < goal) revert GoalNotReached();
        if (withdrawn) revert AlreadyWithdrawn();

        withdrawn = true;
        uint256 amount = totalRaised;
        token.safeTransfer(organizer, amount);
        emit Withdrawn(organizer, amount);
    }

    function refund() external {
        if (block.timestamp < deadline) revert FundingStillOpen();
        if (totalRaised >= goal) revert GoalReached();
        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NoContribution();

        contributions[msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);
        emit Refunded(msg.sender, amount);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./utils/Ownable.sol";
import "./ERC20/IERC20.sol";
import "./ERC20/SafeERC20.sol";

/**
 * To ensure proper governance and reward distribution STEAK tokens
 * are locked in this vesting contract
 */
contract SteakProjectVesting is Ownable {
    using SafeERC20 for IERC20;
    
    // STEAK Token pointer
    IERC20 immutable public steakToken;
    
    string private constant INSUFFICIENT_BALANCE = "Insufficient balance";
    string private constant VESTING_ALREADY_RELEASED = "Vesting already released";
    string private constant NOT_VESTED = "Tokens are locked yet";
    uint256 immutable public creationTime;
    
    // Total amount of tokens which were released from this contract
    uint256 public totalTokensReleased = 0;
    
    event TokenVestingReleased(uint256 indexed weekNumber, uint256 amount);
    event TokenVestingRemoved(uint256 indexed weekNumber, uint256 amount);
    
    
    uint256 SCALING_FACTOR = 10 ** 18; // decimals
    
    // Token amount that should be distributed from week 13 until week 18
    uint256 public FROM_13_TILL_18_WEEKS = 1883700 * SCALING_FACTOR;
    
    // Token amount that should be distributed from week 19 until week 155
    uint256 public FROM_19_TILL_155_WEEKS = 188370 * SCALING_FACTOR;
    
    // Remainig tokens that are left after week 155
    uint256 public FOR_156_WEEK = 151110 * SCALING_FACTOR;
    
    uint256 week = 1 weeks;
    
    // Info of each vesting.
    struct Vesting {
        uint256 amount; // amount that is released at specific point of time
        bool released; // flag that verifies if the funds are already withdrawn
    }
    
    // Info stack about requested vesting at specific period of time.
    mapping(uint256 =>  Vesting) public vestingInfo;
    
    constructor (IERC20 _token) {
        require(address(_token) != address(0x0), "Steak token address is not valid");
        steakToken = _token;

        creationTime = block.timestamp + 1;
    }
    
    // Function returns reward token address
    function token() public view returns (IERC20) {
        return steakToken;
    }
    
    // Function returns timestamp in which funds can be withdrawn
    function releaseTime(uint256 weekNumber) external view returns (uint256) {
        return weekNumber * week + creationTime;
    }
    
    // Function returns amount that can be withdrawn at a specific time
    function vestingAmount(uint256 weekNumber) external view returns (uint256 amount) {
        if (weekNumber >= 13 && weekNumber <= 18) {
            amount = FROM_13_TILL_18_WEEKS;
        }
        if (weekNumber >= 19 && weekNumber <= 155) {
            amount = FROM_19_TILL_155_WEEKS;
        }
        if (weekNumber == 156) {
            amount = FOR_156_WEEK;
        }
    }
    
    // Adds vesting information to vesting array. Can be called only by contract owner
    function removeVesting(uint256 weekNumber) external onlyOwner {
        Vesting storage vesting = vestingInfo[weekNumber];
        require(!vesting.released , VESTING_ALREADY_RELEASED);
        vesting.amount = 0;
        vesting.released = true; // save some gas in the future
        emit TokenVestingRemoved(weekNumber, vesting.amount);
    }
    
    // Function is responsible for releasing the funds at specific point of time
    // Can be called only by contract owner
    function release(uint256 weekNumber) external onlyOwner {
        Vesting storage vesting = vestingInfo[weekNumber];
        require(!vesting.released , VESTING_ALREADY_RELEASED);
        // solhint-disable-next-line not-rely-on-time
        uint256 _releaseTime = weekNumber * week + creationTime;
        require(block.timestamp >= _releaseTime, NOT_VESTED);
        
        uint256 amount;
        if (weekNumber >= 13 && weekNumber <= 18) {
            amount = FROM_13_TILL_18_WEEKS;
        }
        if (weekNumber >= 19 && weekNumber <= 155) {
            amount = FROM_19_TILL_155_WEEKS;
        }
        if (weekNumber == 156) {
            amount = FOR_156_WEEK;
        }
        if (amount > 0) {
            require(steakToken.balanceOf(address(this)) >= vesting.amount, INSUFFICIENT_BALANCE);
            vesting.released = true;
            vesting.amount = amount;
            steakToken.safeTransfer(owner(), vesting.amount);
            totalTokensReleased += vesting.amount;
            emit TokenVestingReleased(weekNumber, vesting.amount);
        }
        
    }
    
    // In a case when there are some Steak tokens left on a contract this function allows the contract owner to retrieve excess tokens
    function retrieveExcessTokens(uint256 _amount) external onlyOwner {
        require(_amount <= steakToken.balanceOf(address(this)), INSUFFICIENT_BALANCE);
        steakToken.safeTransfer(owner(), _amount);
    }
    
}

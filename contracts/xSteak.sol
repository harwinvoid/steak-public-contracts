// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Interfaces/IxSteak.sol";
import "./ERC20/ERC20.sol";
import "./ERC20/IERC20.sol";
import "./utils/Ownable.sol";
import "./ERC20/ERC20Permit.sol";
import "./ERC20/SafeERC20.sol";

contract xSTEAK is ERC20("xSTEAK", "xSTEAK"), ERC20Permit("xSTEAK"), IxSTEAK, Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable steak;

    constructor(IERC20 _steak) {
        steak = _steak;
    }

    function getShareValue() external view override returns (uint256) {
        return totalSupply() > 0
            ? 1e18 * steak.balanceOf(address(this)) / totalSupply()
            : 1e18;
    }

    function deposit(uint256 _amount) public override {
        uint256 totalSteak = steak.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        // if user is first depositer, mint _amount of xSTEAK
        if (totalShares == 0 || totalSteak == 0) {
            _mint(msg.sender, _amount);
        } else {
            // loss of precision if totalSteak is significantly greater than totalShares
            // seeding the pool with decent amount of STEAK prevents this
            uint256 myShare = _amount * totalShares / totalSteak;
            _mint(msg.sender, myShare);
        }
        steak.safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(msg.sender, _amount);
    }

    function depositWithPermit(uint256 _amount, Permit calldata permit) external override {
        IERC20Permit(address(steak)).permit(
            permit.owner,
            permit.spender,
            permit.amount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );
        deposit(_amount);
    }

    function withdraw(uint256 _share) external override {
        uint256 totalShares = totalSupply();
        uint256 shareInSteak = _share * steak.balanceOf(address(this)) / totalShares;
        _burn(msg.sender, _share);
        steak.safeTransfer(msg.sender, shareInSteak);
        emit Withdraw(msg.sender, _share, shareInSteak);
    }

    /// @notice Tokens that are accidentally sent to this contract can be recovered
    function collect(IERC20 _token) external override onlyOwner {
        if (totalSupply() > 0) {
            require(_token != steak, "xSTEAK: cannot collect STEAK");
        }
        uint256 balance = _token.balanceOf(address(this));
        require(balance > 0, "xSTEAK: _token balance is 0");
        _token.safeTransfer(msg.sender, balance);
    }
}
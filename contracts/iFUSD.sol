// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Interfaces/IiFUSD.sol";
import "./ERC20/ERC20.sol";
import "./ERC20/IERC20.sol";
import "./utils/Ownable.sol";
import "./ERC20/ERC20Permit.sol";
import "./ERC20/SafeERC20.sol";

contract iFUSD is ERC20("iFUSD", "iFUSD"), ERC20Permit("iFUSD"), IiFUSD, Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable fusd;

    constructor(IERC20 _fusd) {
        fusd = _fusd;
    }

    function getShareValue() external view override returns (uint256) {
        return totalSupply() > 0
            ? 1e18 * fusd.balanceOf(address(this)) / totalSupply()
            : 1e18;
    }

    function deposit(uint256 _amount) public override {
        uint256 totalFUSD = fusd.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        // if user is first depositer, mint _amount of xFUSD
        if (totalShares == 0 || totalFUSD == 0) {
            _mint(msg.sender, _amount);
        } else {
            // loss of precision if totalFUSD is significantly greater than totalShares
            // seeding the pool with decent amount of FUSD prevents this
            uint256 myShare = _amount * totalShares / totalFUSD;
            _mint(msg.sender, myShare);
        }
        fusd.safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(msg.sender, _amount);
    }

    function depositWithPermit(uint256 _amount, Permit calldata permit) external override {
        IERC20Permit(address(fusd)).permit(
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
        uint256 shareInFUSD = _share * fusd.balanceOf(address(this)) / totalShares;
        _burn(msg.sender, _share);
        fusd.safeTransfer(msg.sender, shareInFUSD);
        emit Withdraw(msg.sender, _share, shareInFUSD);
    }

    /// @notice Tokens that are accidentally sent to this contract can be recovered
    function collect(IERC20 _token) external override onlyOwner {
        if (totalSupply() > 0) {
            require(_token != fusd, "iFUSD: cannot collect FUSD");
        }
        uint256 balance = _token.balanceOf(address(this));
        require(balance > 0, "iFUSD: _token balance is 0");
        _token.safeTransfer(msg.sender, balance);
    }
}
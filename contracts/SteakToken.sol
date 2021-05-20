// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./utils/Ownable.sol";
import "./ERC20/ERC20Permit.sol";


/**
 * STEAK is a token which enables the work and token economics of Stake Steak -
 * a cross-chain yield enhancement platform focusing on
 * Automated Market-Making (AMM) Liquidity Providers (LP)
 */
contract SteakToken is ERC20Permit, Ownable {
    
    constructor()  ERC20("SteakToken", "STEAK") ERC20Permit("SteakToken") 
    {
        
    }
    
    
    // Maximum total supply of the token (5M)
    uint256 private _maxTotalSupply = 5000000000000000000000000;

    
    // Returns maximum total supply of the token
    function getMaxTotalSupply() external view returns (uint256) {
        return _maxTotalSupply;
    }
    
    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     * - can be called only by the owner of contract
     */
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }
    
    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }
    
    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: mint to the zero address");
        require(_totalSupply + amount <= _maxTotalSupply, "ERC20: minting more then MaxTotalSupply");
        
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }
}

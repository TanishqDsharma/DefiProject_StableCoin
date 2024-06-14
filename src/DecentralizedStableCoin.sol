//SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import {ERC20Burnable,ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";


/**
 * @title DecentralizedStableCoin
 * @author Tanishq Sharma
 * Collateral: Exogenous (ETH&BTC)
 * minting: Alogrithimic
 * Relative Stablity: Pegged to USD
 * 
 * This is the contract meant to be governed by DCS Engine. This contract is just the ERC20 implmentation of Our StableCoin.
 */
contract DecentralizedStableCoin is ERC20Burnable,Ownable{
    /**errors */
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin","DSC") Ownable(msg.sender) {

    }

    function burn(uint256 _amount) public override onlyOwner{
        uint256 balance = balanceOf(msg.sender);
        if(_amount<=0){
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        if(balance<_amount){
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);

    } 

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool){
        if(_to==address(0)){
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if(_amount<=0){
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

}
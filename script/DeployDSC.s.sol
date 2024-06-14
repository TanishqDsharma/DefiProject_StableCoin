//SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import {Script} from "../lib/forge-std/src/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[]   public  tokenAddresses;
    address[]   public priceFeedAddresses;
    function run() external returns(DecentralizedStableCoin,DSCEngine){
        
        
        
        HelperConfig config = new HelperConfig();
        (  address wethusdpricefeed,
            address btcusdpricefeed,
            address weth,
            address wbtc,uint256 deployerKey)= config.activeNetworkConfig();
        tokenAddresses = [weth,wbtc];
        priceFeedAddresses=[wethusdpricefeed,btcusdpricefeed];
        vm.startBroadcast();
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));
        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (dsc,engine);
    }
}
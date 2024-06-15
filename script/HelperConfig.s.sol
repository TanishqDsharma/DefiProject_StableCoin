//SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import {Script} from "../lib/forge-std/src/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
contract HelperConfig is Script {

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 3500e8;
    int256 public constant BTC_USD_PRICE = 67000e8;
    uint256 public default_Anvil_Key = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig{
        address wethusdpricefeed;
        address btcusdpricefeed;
        address weth;
        address wbtc;
        uint256 deployerkey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor(){
        if(block.chainid==11155111){
            activeNetworkConfig=getSepoliaEthConfig();
        }else{
            activeNetworkConfig=getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns(NetworkConfig memory){
        return NetworkConfig({
            wethusdpricefeed:0x694AA1769357215DE4FAC081bf1f309aDC325306,
            btcusdpricefeed:0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth:0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc:0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerkey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns(NetworkConfig memory){
        if(activeNetworkConfig.wethusdpricefeed!=address(0)){
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethusdpricefeed = new MockV3Aggregator(DECIMALS,ETH_USD_PRICE);
        MockV3Aggregator btcusdpricefeed = new MockV3Aggregator(DECIMALS,BTC_USD_PRICE);

        ERC20Mock wethmock = new ERC20Mock("wrapped Eth","weth",msg.sender, 1000e8);
        ERC20Mock wbtcmock = new ERC20Mock("wrapped btx","wbtc",msg.sender, 1000e8);

        vm.stopBroadcast();
        
        return NetworkConfig({
            wethusdpricefeed:address(ethusdpricefeed),
            btcusdpricefeed:address(btcusdpricefeed),
            weth:address(wethmock),
            wbtc:address(wbtcmock),
            deployerkey: default_Anvil_Key
        });
    }

    
}
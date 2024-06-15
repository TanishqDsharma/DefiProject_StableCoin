//SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;


import {Test,console} from "../../lib/forge-std/src/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

import {DeployDSC} from "../../script/DeployDSC.s.sol";

contract DSCEngineTest is Test{

uint256 public constant STARTING_BALANCE =1e18;
uint256 public constant AMOUNT_COLLATERAL = 10 ether;
uint256 public constant ERC20_STARTING_BALANCE = 10 ether;

DeployDSC deployer;
DSCEngine dsce;
DecentralizedStableCoin dsc;
HelperConfig config;
address ethUsdPriceFeed;
address weth;
address user = makeAddr("USER");

    function setUp() public{
        deployer = new DeployDSC();
        (dsc,dsce,config) = deployer.run();
        (ethUsdPriceFeed,,weth,,) = config.activeNetworkConfig();
        vm.deal(user,STARTING_BALANCE);
        ERC20Mock(weth).mint(user,ERC20_STARTING_BALANCE);
    }

    ////////////////////
   ///// Price Tests ///
  /////////////////////

function testGetUsdValue() public {
    uint256 ethAmount =15e18;
    console.log("ETH Amount is :> ", ethAmount);
    uint256 expectedUSD = 52500e18;
    uint256 actualUSD = dsce.getUsdValue(weth,ethAmount);
    assert(expectedUSD==actualUSD);
}

///////////////////////////////////
///// Deposit Collateral Tests ///
/////////////////////////////////


function testRevertsIfCollateralZero() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
    vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
    dsce.depositCollateral(weth,0);
    vm.stopPrank();

}

}
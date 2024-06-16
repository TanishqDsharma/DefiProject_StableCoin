//SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;


import {Test,console} from "../../lib/forge-std/src/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

import {DeployDSC} from "../../script/DeployDSC.s.sol";

contract DSCEngineTest is Test{

uint256 public constant STARTING_BALANCE =10e18;
uint256 public constant AMOUNT_COLLATERAL = 10 ether;
uint256 public constant ERC20_STARTING_BALANCE = 10 ether;

DeployDSC deployer;
DSCEngine dsce;
DecentralizedStableCoin dsc;
HelperConfig config;
address ethUsdPriceFeed;
address btcUsdPriceFeed;
address weth;
address wbtc;
address user = makeAddr("USER");

    function setUp() public{
        deployer = new DeployDSC();
        (dsc,dsce,config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth,wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(user,ERC20_STARTING_BALANCE);
    }


    ///////////////////////
   // Constructor Tests ///
  ////////////////////////

  address[] public tokenAddresses;
  address[] public priceFeedAddresses;

  function testIfTokenLengthDoesntMatchPriceFeeds() public{
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

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

function testGetTokenAmountFromUsd() public{
    uint256 usdAmount = 35 ether;
    // 3500$ per ETH, 100$ = 35/3500 = 0.01 eth
    uint256 expectedWeth = 0.01 ether;
    uint256 actualWeth = dsce.getTokenAmountFromUsd(weth,usdAmount);
    assertEq(expectedWeth,actualWeth);
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

function testRevertswithUnapprovedCollateral() public{
    ERC20Mock ranToken = new ERC20Mock("RAN","RAN",user,AMOUNT_COLLATERAL);
    vm.startPrank(user);
    vm.expectRevert();
    dsce.depositCollateral(address(ranToken),AMOUNT_COLLATERAL);
    vm.stopPrank();

}

modifier depositCollateral(){
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    
    vm.stopPrank();
    _;
}


function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
    
    (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
    console.log("totalDscMinted is:",totalDscMinted);
    console.log("collateralValueInUsd is:",collateralValueInUsd);
    uint256 expectedTotalDscMinted = 0;
    uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
    assertEq(totalDscMinted, expectedTotalDscMinted);
    assertEq(AMOUNT_COLLATERAL,expectedDepositedAmount);
}
}
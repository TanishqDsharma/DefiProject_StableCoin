//SPDX-License-Identifier:MIT

pragma solidity ^0.8.16;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
 

/**
 * @title DSCEngine
 * @author  Tanishq Sharma
 * 
 * This system is designed to be as minimal as possible, and have tokens maintain a 1 token == 1$ peg
 * This stable coin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algoritmic Stable
 * 
 * Our DSCEngine should always be ovecollateralized, At no point the value of Collateral should be less than or equal to DSC
 * 
 * This is similar to DAI if it has no fees, no governance and only backed by WETH and WBTC
 * 
 * @notice This contract is core of the DCS System and it handle all the logics for minting and redeeming DSC, as well as depositing and withdrawing collateral
 * @notice This contract is very loosely based on DAI
 */

contract DSCEngine is ReentrancyGuard{

    ///////////////////
    ///Errors     /////   
    ///////////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__transferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    
    //////////////////////////
    ///State Variables   /////   
    //////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION=1e10;
    uint256 private constant PRECISION=1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION= 100;
    uint256 private constant MIN_HEALTH_FACTOR=1e18;
    uint256 private constant LIQUIDATION_BONUS= 10; // This means 10% bonus


    mapping(address token=>address priceFeeds) private s_priceFeeds;
    mapping(address user=>mapping(address token => uint256 amount)) private s_CollateralDeposited;
    mapping(address user=>uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////////////
    ///events   /////   
    ///////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed reedeemedFrom, address indexed reedeemedTo, address indexed token, uint256  amount);

    ////////////////////
    ///Modifiers   /////   
    ///////////////////

    modifier moreThanZero(uint256 amount){
        if(amount==0){
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token){
        if(s_priceFeeds[token ]==address(0)){
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ////////////////////
    ///Functions   /////   
    ///////////////////    

    constructor(address[] memory tokenAddresses, 
                address[] memory pricefeedAddresses
                ,address dscAddress)
                
                {
                    if(tokenAddresses.length!=pricefeedAddresses.length){
                        revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength(); 
                    }

                    for(uint256 i=0;i<tokenAddresses.length;i++){
                        
                        s_priceFeeds[tokenAddresses[i]]=pricefeedAddresses[i];
                        s_collateralTokens.push(tokenAddresses[i]);                   
                    }

                    i_dsc = DecentralizedStableCoin(dscAddress);


    }


    /////////////////////////////
    ///External Functions   /////   
    ///////////////////////////// 

    /**
     * 
     * @param tokenCollateralAddress The address of the token depositing as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of decentralized stable coint to mint
     * @notice this function will deposit your collateral and mint dsc in one transaction
     */

    function depositCollateralandMintDsc(address tokenCollateralAddress, 
                        uint256 amountCollateral,  uint256 amountDscToMint) 
            external {
                depositCollateral(tokenCollateralAddress, amountCollateral);
                mintDsc(amountDscToMint);
            }

    /**
     * 
     * @param tokenCollateralAddress The address of the token depositing as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
                address tokenCollateralAddress, 
                uint256 amountCollateral) public 
                moreThanZero(amountCollateral)
                isAllowedToken(tokenCollateralAddress)
                nonReentrant
                {
                    s_CollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__transferFailed();
        }
                }
                
    /**
     * 
     * @param tokenCollateralAddress The address of the token depositing as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToBurn The amount of decentralized stable coint to burn
     * @notice this function burns DSC and reedeem underlying collateral in one transaction
     */

    function redeemCollateraltoDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) 
        external {
            burnDsc(amountDscToBurn);
            reedeemCollateral(tokenCollateralAddress,amountCollateral);
            // the reedeemCollateral already checks for health factor.
        }

    // In order to reedeem collateral:
    // 1) health factor must be over 1 after collateral pulled 


    
    function reedeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) 
                public moreThanZero(amountCollateral)
                nonReentrant{
                    _reedeemCollateral(msg.sender,msg.sender,tokenCollateralAddress,amountCollateral);
                    _revertIFHealthFactorIsBroken(msg.sender);
                }

    //1) In order to mint DSC we need to check collateral value >DSC amount
    /**
     * @notice follow CEI
     * @param amountDscToMint The amount of decentralized stable coin to mint
     * @notice Collateral must be greater than the minimum threashold value
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant{
        s_DSCMinted[msg.sender] += amountDscToMint;
        // if they minted to much exmaple: if they minted 150$ DSC but they only has 100$ worth of ETH, that ways to much, we should 
        // 100 % revert if that happens
        _revertIFHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender,amountDscToMint );
        if(!minted){
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount){
       _burnDsc(amount,msg.sender,msg.sender);
        _revertIFHealthFactorIsBroken(msg.sender);

    }

    /**
     * 
     * @param collateral The erc20 collateral address to liquidate
     * @param user The use who has broken the health factor. Their _healthFactor should be below minimum healthfactor
     * @param debtToCover The amount of DSC want to burn to improve the users health factor
     * @notice you can partially liquidate user
     * @notice you will get liquidation bonus for taking users funds
     * @notice This function working assumes that the protocol will be 200% overcollateralized in order for this to work
     * @notice A known bug would be if the protocol were 100% or less collateralized, 
     *         then we wouldn't be able to incentivize the liquidators.
     * 
     * For example: The price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collateral,address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant{
        
        // First we need to check the health factor of the user
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor<MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOk();
        }

        //Next, we want to burn there DSC Debt
        //And take there collateral
        // For example: bad user: $140 worth of eth collateral and $100 DSC 
        // debttoCover = $100
        // 100 dollar worth of ETH??

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral,debtToCover);

        // Now, for doing this we want a 10% bonus
        // So, we are giving the liquidator 110$ dollars of WETH for $100 DSC
        // We should Implement a feature to liquidate in the event the protocol is insolvent 
        
        uint256 bonusCollateral = (tokenAmountFromDebtCovered*LIQUIDATION_BONUS)/LIQUIDATION_PRECISION;
        uint256 totalCollateralToReedeem = tokenAmountFromDebtCovered+bonusCollateral; 
        _reedeemCollateral(user,msg.sender,collateral,totalCollateralToReedeem);
        _burnDsc(debtToCover, user,msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if(endingUserHealthFactor<=userHealthFactor){
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIFHealthFactorIsBroken(msg.sender);


    }

    function getHealthFactor() external {}

    /////////////////////////////////////////
    ///Private and Internal Functions   /////   
    ////////////////////////////////////////

    /**
     * 
     * @dev Low-Level Internal Function, do not call unless the function calling it is checking for health factors is being broken
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private{
        s_DSCMinted[onBehalfOf]-=amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this),amountDscToBurn);
        if(!success){
            revert DSCEngine__transferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _reedeemCollateral(address from, address to,
            address tokenCollateralAddress,
            uint256 amountCollateral
            ) private {

                s_CollateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
                //Since we are changing the state lets emit an event 
                emit CollateralRedeemed(from,to,tokenCollateralAddress,amountCollateral);
                bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
                if(!success){
                    revert DSCEngine__transferFailed();
                }

    }


    /**
     * 
     * Returns how close to liquidation a user is 
     * If a user goes below 1, then they get liquidated 
     */

    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted,uint256 collateralValueInUsd)  {

        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);        
    }

    function _healthFactor(address user) private view returns(uint256) {

        //To calculate this we need to have both the 
        //1. total DSC Minted
        //2. total collateral value
        (uint256 totalDscMinted, uint256  collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd*LIQUIDATION_THRESHOLD) /LIQUIDATION_PRECISION;
        return (collateralValueInUsd*PRECISION)/totalDscMinted;

        //This will give true healt factor and if its less than one we will get liquidated.

    }

    function _revertIFHealthFactorIsBroken(address user) internal view{
        // 1. Check health factor (do they have enough collateral?)
        // 2. Revert if they dont have good health factor

        uint256 userhealthFactor = _healthFactor(user);
        if(userhealthFactor<MIN_HEALTH_FACTOR){
            revert DSCEngine__BreaksHealthFactor(userhealthFactor);
        }

    }

    /////////////////////////////////////////////
    ///Public and External View Functions   /////   
    ///////////////////////////////////////////// 

    function getTokenAmountFromUsd(address token, uint256 usdamountinwei)
        public view returns(uint256){
            //1. First, we need to get the price of the token ETH
            AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
            (,int256 price,,,) = priceFeed.latestRoundData();
            return(usdamountinwei*PRECISION)/(uint256(price) * ADDITIONAL_FEED_PRECISION);
        }

    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUsd){
        //To get the actual value we need to:
            // loop through collateral token, get the amount they have deposited and map it to price
            // to get the usd value

        for(uint256 i=0;i<s_collateralTokens.length;i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_CollateralDeposited[user][token];
            totalCollateralValueInUsd +=  getUsdValue(token,amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256 ){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        // The returned price will have 8 decimal places so if suppose 1 ETH = 1000$ then the returned value is 1000*1e8

        return ((uint256(price)*ADDITIONAL_FEED_PRECISION)*amount)/PRECISION;

    }

    function getAccountInformation(address user)
    external
    view
    returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
{
    return _getAccountInformation(user);
}
}
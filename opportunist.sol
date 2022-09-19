/*SPDX-License-Identifier: NONE*/

pragma solidity ^0.5.0;




import "./FlashLoanReceiverBase.sol";
import "./ILendingPoolAddressesProvider.sol";
import "./ILendingPool.sol";




contract Ownable {
  address public owner;


  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  constructor() public {
    owner = msg.sender;
  }


  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }


  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) onlyOwner public {
    require(newOwner != address(0));
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

}







interface IRouter{
    function WETH() external pure returns (address);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function factory() external view returns (address);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}

interface IFactory{
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IPair{
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}


interface IBEP20 {
    function approve(address spender, uint256 amount) external returns (bool);
}




contract Opportunist is FlashLoanReceiverBase, Ownable{
    using SafeMath for uint256;
    
      /**
     * Some variables and events
     */
     
    address public exchangeToken = address(0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa); //DAI, BUSD, BAT..,i.e, the token that we want to trade in
    address[] public routers = [0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506,0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D]; // Router addresses of various swaps. Be careful, once you push any address you can't delete it.
    address public bnb = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;  // Base token. It has to be BNB or ETH, i.e, this address as per the docs
    
    uint256 public totalNumberOfTrades; 
    uint256 public totalRecharges; 
    uint256 public totalWithdrawn; 
    uint256 public totalProfit; 
    
    event SwappedFromBnBToToken(uint amount, uint256 buyPrice, address buyOnSwap);
    event SwappedFromTokenToBnB(uint amount, uint sellPrice, address soldOnSwap);
    
    
    // Get lending pool addressesProvider address from the multiplier-finance docs and pass it as the constructor
    // Multiplier-finance Mainnet addressesProvider contract address is 0xCc0479a98cC66E85806D0Cd7970d6e07f77Fd633
    constructor(ILendingPoolAddressesProvider _addressesProvider) FlashLoanReceiverBase(_addressesProvider) public {}

    function setExchangeToken(address _exchangeToken) onlyOwner external returns(bool){
        require(_exchangeToken != address(0), "can not set zero address");
        exchangeToken = _exchangeToken;
        return true;
    }
   
    function addRouter(address _router) onlyOwner external returns(bool added, address) {
        require(_router != address(0), "can not set zero address");
        routers.push(_router);
        return(true, _router);
    }
    
    function getUtilAddresses(address routerAddress) internal view returns(address[] memory){
        address[] memory paths = new address[](4);
        paths[0] = IRouter(routerAddress).WETH();
        paths[1] = IRouter(routerAddress).factory();
        paths[2] = IFactory(paths[1]).getPair(paths[0], exchangeToken);
        require(paths[2] != address(0), "No LP pair found with the given exchange token. Try setting another exchange token");
        paths[3] = IPair(paths[2]).token0();
        return paths;
    }
    
    /**
     * Get selling price of 1 bnb
     */
    function getSellPrice(address routerAddress, uint256 tokenAmount) public view returns(uint256){
        uint256 price;
        address[] memory paths = new address[](4);
        paths = getUtilAddresses(routerAddress);

        (uint112 reserve0, uint112 reserve1,) = IPair(paths[2]).getReserves();
        if(paths[3] == paths[0]){
            price = IRouter(routerAddress).getAmountOut(tokenAmount, reserve1, reserve0);
            return price;
        }
        price = IRouter(routerAddress).getAmountOut(tokenAmount, reserve0, reserve1);
        return price;
    }
    
    /**
     * Get buying price of 1 bnb
     */
    function getBuyPrice(address routerAddress, uint256 tokenAmount) public view returns(uint256){
        uint256 price;
        address[] memory paths = new address[](4);
        paths = getUtilAddresses(routerAddress);

        (uint112 reserve0, uint112 reserve1,) = IPair(paths[2]).getReserves();
        if(paths[3] == paths[0]){
            price = IRouter(routerAddress).getAmountIn(tokenAmount, reserve0, reserve1);
            return price;
        }
        price = IRouter(routerAddress).getAmountIn(tokenAmount, reserve1, reserve0);
        return price;
    }
    
    /**
     * Checking for minBuyPrice and maxSellPrice for a given pair on the given swaps
     */
    function checkAllSwapsAndGetProfitSpread(uint256 tokenAmount) public view returns(uint256, address, address, uint256, uint256){
        uint256 minBuyPrice = getBuyPrice(routers[0], tokenAmount);
        uint256 maxSellPrice = getSellPrice(routers[0], tokenAmount);
        uint32 sellIndex;
        uint32 buyIndex;
        for(uint32 i = 0; i < routers.length; i++){
            
            if(getSellPrice(routers[i], tokenAmount) > maxSellPrice){
                maxSellPrice = getSellPrice(routers[i], tokenAmount);
                sellIndex = i;
            }
            if(getBuyPrice(routers[i], tokenAmount) < minBuyPrice){
                minBuyPrice = getBuyPrice(routers[i], tokenAmount);
                buyIndex = i;
            }
            
        }
        if(minBuyPrice < maxSellPrice){
            uint256 _margin = maxSellPrice - minBuyPrice;
            return (_margin, routers[buyIndex], routers[sellIndex], minBuyPrice, maxSellPrice);
        }
        return (0, routers[buyIndex], routers[sellIndex], minBuyPrice, maxSellPrice);
    }
    
    // Do arbitrage without getting flash loan
    function executeSwapOnProfit(uint256 _forAmount, uint256 _totalFee) public{
        (uint256 margin, address buyOn, address sellOn, uint256 minBuyPrice, uint256 maxSellPrice) = checkAllSwapsAndGetProfitSpread(_forAmount);
        require(margin > 0, "You missed the window!");
        require(margin > _totalFee, "Not enough to earn, fee is too much");
        
        require(IBEP20(IRouter(buyOn).WETH()).approve(address(buyOn), minBuyPrice), 'approve failed.');
        address[] memory path = new address[](2);
        path[0] = IRouter(buyOn).WETH();
        path[1] = address(exchangeToken);
        
        IRouter(buyOn).swapETHForExactTokens.value(minBuyPrice)(_forAmount, path, address(this), block.timestamp+100);
        emit SwappedFromBnBToToken(_forAmount, minBuyPrice, buyOn);

    
        require(IBEP20(exchangeToken).approve(address(sellOn), _forAmount), 'approve failed.');
        path = new address[](2);
        path[0] = address(exchangeToken);
        path[1] = IRouter(sellOn).WETH();
        
        IRouter(sellOn).swapExactTokensForETH(_forAmount, maxSellPrice, path, address(this), block.timestamp+100);
        emit SwappedFromTokenToBnB(_forAmount, maxSellPrice, sellOn);
        uint256 _profit = margin.sub(_totalFee);
        
        totalProfit = totalProfit.add(_profit);
        totalNumberOfTrades = totalNumberOfTrades.add(1);
    }
    
    // Dp arbitrage with flash loan 
    function doArbitrageWithFlashLoan(uint _forAmount) external onlyOwner{
        (uint margin,,,uint requiredLoanAmountInBNB,) = checkAllSwapsAndGetProfitSpread(_forAmount);
        require(margin > 0 , "Not much to earn, try again");
        // uint256 requiredLoanAmount = getBuyPrice();
        flashloan(requiredLoanAmountInBNB, _forAmount);
    }
    
    // called by lending pool contract after flash loan
    function executeOperation(address _reserve, uint256 _amount, uint256 _fee, bytes calldata _params) external {
        require(_amount <= getBalanceInternal(address(this), _reserve), "Invalid balance, was the flashLoan successful?");
        (uint amount) = abi.decode(_params, (uint));
        (uint _margin,,,,) = checkAllSwapsAndGetProfitSpread(amount);
        require(_margin > _fee, "Fee is greater than margin");
        executeSwapOnProfit(amount, _fee);
        // Time to transfer the funds back
        uint totalDebt = _amount.add(_fee);
        transferFundsBackToPoolInternal(_reserve, totalDebt);
    }
    // get flash loan from lending pool
    function flashloan(uint _loanAmount, uint _forAmount) internal{
        ILendingPool lendingPool = ILendingPool(addressesProvider.getLendingPool());
       
        (,uint256 availableLiquidity,,,,,,,,,,,) = lendingPool.getReserveData(bnb);
        require(availableLiquidity > _loanAmount, "not enough liquidity for bnb in the lending pool");
        bytes memory data = abi.encode(_forAmount);
        uint amount = _loanAmount;
        address asset = address(bnb); // mainnet BNB
        
        lendingPool.flashLoan(address(this), asset, amount, data);
    }
    // receive and rescue BNB
    function recharge() external payable{
        totalRecharges = totalRecharges.add(msg.value);
    }
    function rescueBNB() external onlyOwner {
        totalWithdrawn = totalWithdrawn.add(address(this).balance);
        msg.sender.transfer(address(this).balance);
    }
    function contractBalance() external view returns(uint256){
        return address(this).balance;
    }
   
}

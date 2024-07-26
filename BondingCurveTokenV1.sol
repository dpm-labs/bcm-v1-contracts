// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {Test, console} from "forge-std/Test.sol";

interface IMarket {
    function getPostExpirationDuration() external view returns (uint256);
}

contract BondingCurveToken is ERC20, Ownable, Pausable {
    
    uint8 public constant DECIMALS = 18;
    uint256 public constant DECIMAL_FACTOR = 10**DECIMALS;

    // uint256 public reserveBalance;
    address public marketContract;
    bool public tradingPaused;
    uint256 public expirationTime;
    bool public marketResolved;
    uint256 public marketId;
    uint256 public optionId;
    uint256 public basePrice; 
    uint256 public slope; 
    uint256 public resumeTradingTimestamp;

    address public creator;
    address public platform;
    uint256 public feePercentage = 15; // Basis points, i.e., 1.5%

    modifier onlyMarket() {
        require(msg.sender == marketContract, "Only market contract can call this function");
        _;
    }

    event SlopeChanged(uint256 marketId, uint256 optionId, uint256 newSlope);
    event BasePriceChanged(uint256 marketId, uint256 optionId, uint256 newBasePrice);
    event TradingPaused(uint256 marketId, uint256 optionId);
    event TradingResumed(uint256 marketId, uint256 optionId);
    event BuyToken(uint256 marketId, uint256 optionId, address walletAddress, uint256 eth, uint256 amount, uint256 avgPrice);
    event SellToken(uint256 marketId, uint256 optionId, address walletAddress, uint256 eth, uint256 amount, uint256 avgPrice);
    event PriceChange(uint256 marketId, uint256 optionId, uint256 timestamp, uint256 newPrice);
    event FeeTransferred(uint256 marketId, uint256 optionId, uint256 creatorFee, uint256 platformFee, string actionType);


    constructor(
        address _marketContract,
        string memory name,
        string memory symbol,
        uint256 _expirationTime,
        uint256 _marketId,
        uint256 _optionId,
        address _creator,
        address _platform
    ) ERC20(name, symbol) Ownable(msg.sender) {
        marketContract = _marketContract;
        // reserveBalance = 0;
        basePrice = 300000000000000; // initial price 0.0003 ETH 
        slope = 30000000000000; // increase 0.00003 ETH for each token 
        expirationTime = _expirationTime;
        marketResolved = false;
        marketId = _marketId;
        optionId = _optionId;
        creator = _creator;
        platform = _platform;
    }

    function setMarketResolved(bool _resolved) external onlyMarket {
        marketResolved = _resolved;
    }

    function setSlope(uint256 newSlope) external onlyMarket {
        slope = newSlope;
        emit SlopeChanged(marketId, optionId, newSlope);
    }

    function setBasePrice(uint256 newBasePrice) external onlyMarket {
        basePrice = newBasePrice;
        emit BasePriceChanged(marketId, optionId, newBasePrice);
    }

    function pauseTrading() external onlyMarket {
        tradingPaused = true;
        emit TradingPaused(marketId, optionId);
    }

    function resumeTrading() external onlyMarket {
        tradingPaused = false;
        emit TradingResumed(marketId, optionId);
    }

    function setResumeTradingTimestamp(uint256 timestamp) external onlyMarket {
        resumeTradingTimestamp = timestamp;
    }

    function calculateTotalCost(uint256 tokenAmount) public view returns (uint256) {
        uint256 supply = totalSupply();
    
        uint256 baseCost = basePrice * tokenAmount / 1e18;

        uint256 tokenAmountTimesSupply = tokenAmount * supply / 1e18;
        uint256 tokenAmountTimesTokenAmountMinusOne;
       
        tokenAmountTimesTokenAmountMinusOne = (tokenAmount * tokenAmount) / (2 * 1e18);

        uint256 incrementalCost = slope * (tokenAmountTimesSupply + tokenAmountTimesTokenAmountMinusOne) / 1e18;

        uint256 totalCost = baseCost + incrementalCost;

        uint256 creatorShare = totalCost * feePercentage / 1000;
        uint256 platformShare = totalCost * feePercentage / 1000;
        totalCost += creatorShare + platformShare;


        return totalCost;
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return z;
    }


    function calculateTotalProceeds(uint256 tokenAmount) public view returns (uint256) {
        uint256 supply = totalSupply();

        require(tokenAmount <= supply, "Token amount exceeds total supply");

        uint256 baseProceeds = (basePrice * tokenAmount) / 1e18;

        uint256 supplyAfterSale = supply - tokenAmount;
        uint256 tokenAmountTimesSupply = (tokenAmount * supplyAfterSale) / 1e18;
        uint256 tokenAmountTimesTokenAmountMinusOne;
    
        tokenAmountTimesTokenAmountMinusOne = (tokenAmount * tokenAmount) / (2 * 1e18);

        uint256 incrementalProceeds = (slope * (tokenAmountTimesSupply + tokenAmountTimesTokenAmountMinusOne)) / 1e18;

        uint256 totalProceeds = baseProceeds + incrementalProceeds;

        uint256 creatorShare = totalProceeds * feePercentage / 1000;
        uint256 platformShare = totalProceeds * feePercentage / 1000;
        totalProceeds -= (creatorShare + platformShare);


        return totalProceeds;
    }

     function calculatePrice(uint256 supply) public view returns (uint256) {
        uint256 price = basePrice + (slope * supply / 1e18);
        return price;
    }

    function calculateTokenAmount(uint256 ethAmount) public view returns (uint256) {
        uint256 supply = totalSupply();

        if (ethAmount == 0) {
            return 0;
        }

        uint256 a = slope / 2;
        uint256 b = (slope * supply / 1e18) + basePrice;
        uint256 c = ethAmount;  

        uint256 discriminant = b * b + 4 * a * c ;
        require(discriminant >= 0, "No real solution");

        console.log("Discriminant:", discriminant);

        uint256 sqrtDiscriminant = sqrt(discriminant);

        console.log("Sqrt Discriminant:", sqrtDiscriminant);

        uint256 numerator = sqrtDiscriminant - b;
        uint256 denominator = 2 * a;

        require(denominator > 0, "Denominator must be greater than zero");

        uint256 tokenAmount = numerator * 1e18 / denominator;

        console.log("Token Amount:", tokenAmount);

        return tokenAmount;
    }

     function buyFromContract(uint256 amount, uint256 ethAmount) external payable onlyMarket {
        console.log('===buyFromContract===');
        console.log('address(this).balance:',address(this).balance);
        console.log('amount:',amount);
        console.log('ethAmount:',ethAmount);
        console.log('msg.value:',msg.value);
        // require(address(marketContract).balance >= ethAmount, "Insufficient balance in contract");
        require(msg.value >= ethAmount, "Incorrect payment amount");
        // require(ethAmount >= calculateTotalCost(amount), "Insufficient payment");
        

        // 執行購買邏輯
        _mint(marketContract, amount);
        // reserveBalance += ethAmount;

        console.log('===over buyFromContract===');

        emit BuyToken(marketId, optionId, marketContract, ethAmount, amount, ethAmount / amount);
        emit PriceChange(marketId, optionId, block.timestamp, calculatePrice(totalSupply()));
    }

    function sendLoseOptionPriceTo0Event() external onlyMarket {
        emit PriceChange(marketId, optionId, block.timestamp, 0);
    }


    function buy(uint256 amount) external payable whenNotPaused {
        checkTradingStatus();

        uint256 tokenAmount = amount;
        uint256 cost = calculateTotalCost(tokenAmount);

        uint256 creatorShare = cost * feePercentage / (1000+feePercentage+feePercentage);
        uint256 platformShare = cost * feePercentage / (1000+feePercentage+feePercentage);
        // uint256 totalCost = cost + creatorShare + platformShare;

        require(msg.value >= cost, "Insufficient payment");

        _mint(msg.sender, tokenAmount);
        // reserveBalance += cost;

        uint256 avgPrice = cost * 1e18 / tokenAmount;

        emit BuyToken(marketId, optionId, msg.sender, cost, tokenAmount, avgPrice);
        emit PriceChange(marketId, optionId, block.timestamp, calculatePrice(totalSupply()));

        if (msg.value > cost) {
            uint256 refund = msg.value - cost;
            payable(msg.sender).transfer(refund);
        }

        payable(creator).transfer(creatorShare);
        payable(platform).transfer(platformShare);
        emit FeeTransferred(marketId, optionId, creatorShare, platformShare, "buy");

    }

    function sell(uint256 amount) external whenNotPaused returns (uint256) {
        checkTradingStatus();

        uint256 tokenAmount = amount;

        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient balance to sell");

        uint256 proceeds = calculateTotalProceeds(tokenAmount);

        uint256 origin_proceeds = proceeds * 1000 / (1000-feePercentage-feePercentage);
        uint256 creatorShare = origin_proceeds * feePercentage / 1000;
        uint256 platformShare = origin_proceeds * feePercentage / 1000;

        // uint256 creatorShare = proceeds * feePercentage / (1000-feePercentage-feePercentage);
        // uint256 platformShare = proceeds * feePercentage / (1000-feePercentage-feePercentage);

        console.log('creatorShare:',creatorShare);
        console.log('platformShare:',platformShare);
        // uint256 totalProceeds = proceeds - creatorShare - platformShare;

        console.log('proceeds:',proceeds);

        console.log('eth in contract:',address(this).balance);

        require(address(this).balance >= proceeds + creatorShare + platformShare, "Insufficient reserve to pay out");

        _burn(msg.sender, tokenAmount);
        // reserveBalance -= proceeds;

        uint256 avgPrice = proceeds * 1e18 / tokenAmount;

        payable(msg.sender).transfer(proceeds);
        payable(creator).transfer(creatorShare);
        payable(platform).transfer(platformShare);

        emit SellToken(marketId, optionId, msg.sender, proceeds, tokenAmount, avgPrice);
        emit PriceChange(marketId, optionId, block.timestamp, calculatePrice(totalSupply()));
        emit FeeTransferred(marketId, optionId, creatorShare, platformShare, "sell");


        return proceeds;
    }

    function checkTradingStatus() public view {
        if (!marketResolved) {
            uint256 postExpirationDuration = IMarket(marketContract).getPostExpirationDuration();
            require(
                (block.timestamp < expirationTime || block.timestamp > expirationTime + postExpirationDuration) && !tradingPaused, 
                "Market is expired and trading is not allowed"
            );
        } else {
            require(
                block.timestamp >= resumeTradingTimestamp, 
                "Market is resolved and trading is not allowed yet"
            );
        }
    }

    function withdraw(uint256 amount) external onlyMarket {
        require(amount <= address(this).balance, "Insufficient reserve balance");
        payable(marketContract).transfer(amount);
    }
}

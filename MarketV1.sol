// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./BondingCurveTokenV1.sol";
import "./BondingCurveTokenFactoryV1.sol";
import {Test, console} from "forge-std/Test.sol";

contract Market is Ownable, Pausable {

    struct Option {
        string name;
        address tokenAddress;
        uint256 optionId;
    }

    struct MarketStruct {
        string name;
        Option[] options;
        uint256 expirationTime;
        bool settled;
        address creator;
        uint256 winningOptionIndex;
    }

    mapping(uint256 => MarketStruct) public markets;
    uint256 public marketCount;
    BondingCurveTokenFactory public tokenFactory;
    address public platformAddress;
    
    uint256 public resumeTradingDuration = 12 hours;
    uint256 public postExpirationDuration = 2 days;

    event MarketCreated(uint256 marketId, string name, uint256 expirationTime, uint256 optionCount, address creator, address[] optionAddresses);
    event MarketTempResolved(uint256 marketId);
    event MarketResolved(uint256 marketId, uint256 winningOptionIndex, uint256[] ethBalances, uint256 remainingETH);
    event AllETHWithdrawn(uint256 indexed marketId, uint256 amount);
    event ResolvedTokensSold(uint256 indexed marketId, uint256 winningOptionIndex, uint256 tokenAmount, uint256 ethReceived);

    constructor(address initialOwner, address _tokenFactory) Ownable(initialOwner) {
        tokenFactory = BondingCurveTokenFactory(_tokenFactory);
        marketCount = 0;
        platformAddress = address(0x78200F6a304E216268bed6Fc5289BdE077fd7583);
    }

    receive() external payable {}

    function createMarket(string memory name, string[] memory optionNames, uint256 expirationTime) external returns (uint256, address[] memory) {
        uint256 currentMarketId = marketCount;
        MarketStruct storage market = markets[currentMarketId];
        market.name = name;
        market.creator = msg.sender;
        market.expirationTime = expirationTime;
        
        address[] memory optionAddresses = new address[](optionNames.length);

        for (uint256 i = 0; i < optionNames.length; i++) {
            address tokenAddress = tokenFactory.createToken(
                optionNames[i],
                address(this),
                expirationTime,
                currentMarketId,
                i,
                market.creator,
                platformAddress
            );
            market.options.push(Option({
                name: optionNames[i],
                tokenAddress: tokenAddress,
                optionId: i
            }));
            optionAddresses[i] = tokenAddress;
        }

        emit MarketCreated(currentMarketId, name, expirationTime, optionNames.length, msg.sender, optionAddresses);
        marketCount++;
        return (currentMarketId, optionAddresses);
    }

    function getMarket(uint256 marketId, uint256 random) public view returns (string memory, Option[] memory, uint256, bool, address, uint256) {
        require(marketId < marketCount, "Market ID out of range");
        MarketStruct storage market = markets[marketId];
        return (market.name, market.options, market.expirationTime, market.settled, market.creator,block.timestamp);
    }

    function getResolveInfo(uint256 marketId) public view returns (bool, uint256) {
        require(marketId < marketCount, "Market ID out of range");
        MarketStruct storage market = markets[marketId];
        return (market.settled, market.winningOptionIndex);
    }

    function resolveMarket(uint256 marketId, uint256 winningOptionIndex) external {
        MarketStruct storage market = markets[marketId];
        require(msg.sender == market.creator, "Only market creator can resolve the market");
        require(!market.settled, "Market already settled");

        market.settled = true;
        market.winningOptionIndex = winningOptionIndex;

        uint256 totalETH = 0;
        uint256[] memory ethBalances = new uint256[](market.options.length);

        for (uint256 i = 0; i < market.options.length; i++) {
            BondingCurveToken optionToken = BondingCurveToken(market.options[i].tokenAddress);
            // uint256 tokenBalance = optionToken.reserveBalance();
            uint256 tokenBalance = address(optionToken).balance;
            ethBalances[i] = tokenBalance;
            console.log("Option", i, "balance:", tokenBalance);
            if (i != winningOptionIndex && tokenBalance > 0) {
                console.log("Option", i, "balance:", tokenBalance);
                optionToken.withdraw(tokenBalance);
                totalETH += tokenBalance;
                optionToken.sendLoseOptionPriceTo0Event();
            }
            optionToken.setResumeTradingTimestamp(block.timestamp + resumeTradingDuration); // 設定繼續交易的 timestamp
        }

        uint256 remainingETH = totalETH;

        Option storage winningOption = market.options[winningOptionIndex];
        BondingCurveToken winningToken = BondingCurveToken(winningOption.tokenAddress);

        uint256 tokenAmount = winningToken.calculateTokenAmount(remainingETH);

        if (tokenAmount > 0) {
            winningToken.buyFromContract{value: remainingETH}(tokenAmount, remainingETH);
        }

        for (uint256 i = 0; i < market.options.length; i++) {
            BondingCurveToken optionToken = BondingCurveToken(market.options[i].tokenAddress);
            // optionToken.resumeTrading();
            optionToken.setMarketResolved(true);
        }

        emit MarketResolved(marketId, winningOptionIndex, ethBalances, remainingETH);
    }

    function getMarketAllOptionsEth(uint256 marketId, uint256 random) external view returns (uint256[] memory) {
        MarketStruct storage market = markets[marketId];
        uint256[] memory ethBalances = new uint256[](market.options.length);
        for (uint256 i = 0; i < market.options.length; i++) {
            // ethBalances[i] = BondingCurveToken(market.options[i].tokenAddress).reserveBalance();
            ethBalances[i] = address(BondingCurveToken(market.options[i].tokenAddress)).balance;
        }
        return ethBalances;
    }

    function stopMarket(uint256 marketId) external onlyOwner whenNotPaused {
        MarketStruct storage market = markets[marketId];
        require(!market.settled, "Market already settled");

        for (uint256 i = 0; i < market.options.length; i++) {
            BondingCurveToken(market.options[i].tokenAddress).pauseTrading();
        }
        emit MarketTempResolved(marketId);
    }

    function resumeMarket(uint256 marketId) external onlyOwner whenNotPaused {
        MarketStruct storage market = markets[marketId];

        for (uint256 i = 0; i < market.options.length; i++) {
            BondingCurveToken(market.options[i].tokenAddress).resumeTrading();
        }
    }

    function setTokenBasePrice(uint256 marketId, uint256 tokenIndex, uint256 newBasePrice) external onlyOwner {
        MarketStruct storage market = markets[marketId];
        BondingCurveToken(market.options[tokenIndex].tokenAddress).setBasePrice(newBasePrice);
    }

    function setTokenSlope(uint256 marketId, uint256 tokenIndex, uint256 newSlope) external onlyOwner {
        MarketStruct storage market = markets[marketId];
        BondingCurveToken(market.options[tokenIndex].tokenAddress).setSlope(newSlope);
    }

    function getOptionTokenAddresses(uint256 marketId) external view returns (address[] memory) {
        Option[] memory options = markets[marketId].options;
        address[] memory tokenAddresses = new address[](options.length);
        for (uint256 i = 0; i < options.length; i++) {
            tokenAddresses[i] = options[i].tokenAddress;
        }
        return tokenAddresses;
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function setPlatformAddress(address _platformAddress) external onlyOwner {
        platformAddress = _platformAddress;
    }

    function setResumeTradingDuration(uint256 _duration) external onlyOwner {
        resumeTradingDuration = _duration;
    }

    function setPostExpirationDuration(uint256 _duration) external onlyOwner {
        postExpirationDuration = _duration;
    }

    function getResumeTradingDuration() external view returns (uint256) {
        return resumeTradingDuration;
    }

    function getPostExpirationDuration() external view returns (uint256) {
        return postExpirationDuration;
    }
}

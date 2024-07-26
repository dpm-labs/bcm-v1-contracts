// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BondingCurveTokenV1.sol";

contract BondingCurveTokenFactory {
    address[] public tokens;

    event TokenCreated(address indexed tokenAddress, uint256 indexed marketId, uint256 indexed optionId);

    function createToken(
        string memory name,
        address marketContract,
        uint256 expirationTime,
        uint256 marketId,
        uint256 optionId,
        address creator,
        address platform
    ) external returns (address) {
        BondingCurveToken token = new BondingCurveToken(
            marketContract,
            name,
            name,
            expirationTime,
            marketId,
            optionId,
            creator,
            platform
        );
        token.transferOwnership(msg.sender);
        tokens.push(address(token));
        emit TokenCreated(address(token), marketId, optionId);
        return address(token);
    }

    function getTokens() external view returns (address[] memory) {
        return tokens;
    }

    function getLastToken() external view returns (address) {
        require(tokens.length > 0, "No tokens created yet");
        return tokens[tokens.length - 1];
    }
}

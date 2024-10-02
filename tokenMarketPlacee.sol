// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // Import ReentrancyGuard
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol"; //to console output

contract TokenMarketPlace is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public tokenPrice = 1e13 wei; // 0.00001 ether per Immortal token
    uint256 public constant MIN_PRICE = 1e12; // Minimum token price (0.000001 ETH)
    uint256 public constant MAX_PRICE = 1e18; // Maximum token price (1 ETH)

    uint256 public totalBuyVolume = 0;
    uint256 public totalSellVolume = 0;

    uint256 public constant smoothingFactor = 1e18; // Adjust this to control price fluctuations

    IERC20 public imlToken;

    event TokenPriceUpdated(uint256 newPrice);
    event TokenBought(address indexed buyer, uint256 amount, uint256 totalCost);
    event TokenSold(
        address indexed seller,
        uint256 amount,
        uint256 totalEarned
    );
    event TokensWithdrawn(address indexed owner, uint256 amount);
    event EtherWithdrawn(address indexed owner, uint256 amount);

    constructor(address _imlToken) Ownable(msg.sender) {
        imlToken = IERC20(_imlToken);
    }

    // Adjust price based on the volume of tokens bought and sold
    function adjustTokenPrice() internal {
        uint256 priceChangeFactor;

        // Price increases if buy volume is greater than sell volume
        if (totalBuyVolume > totalSellVolume) {
            uint256 buySellRatio = totalBuyVolume.mul(1e18).div(
                totalSellVolume.add(1)
            ); // Add 1 to avoid division by zero
            priceChangeFactor = buySellRatio.div(smoothingFactor); // Apply smoothing factor
            tokenPrice = tokenPrice.mul(100 + priceChangeFactor).div(100);
        }
        // Price decreases if sell volume is greater than buy volume
        else if (totalSellVolume > totalBuyVolume) {
            uint256 sellBuyRatio = totalSellVolume.mul(1e18).div(
                totalBuyVolume.add(1)
            ); // Add 1 to avoid division by zero
            priceChangeFactor = sellBuyRatio.div(smoothingFactor);
            tokenPrice = tokenPrice.mul(100 - priceChangeFactor).div(100);
        }

        // Ensure token price stays within defined boundaries
        if (tokenPrice < MIN_PRICE) {
            tokenPrice = MIN_PRICE;
        } else if (tokenPrice > MAX_PRICE) {
            tokenPrice = MAX_PRICE;
        }

        emit TokenPriceUpdated(tokenPrice); // Emit an event to update the frontend
    }

    // Buy tokens from the marketplace
    function buyIMLToken(uint256 _amountOfToken) public payable nonReentrant{
        require(_amountOfToken > 0, "Amount must be greater than 0");
        uint256 TotalCost = _amountOfToken.mul(tokenPrice).div(1e18);
        require(msg.value >= TotalCost, "Insufficient Ether sent");

        totalBuyVolume = totalBuyVolume.add(_amountOfToken.div(1e18)); // Update buy volume
        imlToken.safeTransfer(msg.sender, _amountOfToken);
        emit TokenBought(msg.sender, _amountOfToken, TotalCost);

        adjustTokenPrice();
        console.log("price after buying", tokenPrice);

        // // Refund excess Ether if any
        if (msg.value > TotalCost) {
            payable(msg.sender).transfer(msg.value.sub(TotalCost));
        }
        emit TokenPriceUpdated(tokenPrice);
    }

    // Calculate the current price for a given amount of tokens
    function calculateTokenPrice(uint256 _amountOfTokens)
        public
        view
        returns (uint256)
    {
        require(_amountOfTokens > 0, "Amount of tokens must be greater than 0");
        uint256 amountToPay = _amountOfTokens.mul(tokenPrice).div(1e18);
        return amountToPay;
    }

    // Sell tokens back to the marketplace
    function sellIMLToken(uint256 _amountOfToken) public nonReentrant{
        require(_amountOfToken > 0, "Amount must be greater than 0");
        uint256 totalEarned = _amountOfToken.mul(tokenPrice).div(1e18);

        // Ensure the contract has enough Ether to pay the seller
        require(
            address(this).balance >= totalEarned,
            "Not enough Ether in contract"
        );

        totalSellVolume = totalSellVolume.add(_amountOfToken.div(1e18)); // Update sell volume
        imlToken.safeTransferFrom(msg.sender, address(this), _amountOfToken);
        payable(msg.sender).transfer(totalEarned);
        emit TokenSold(msg.sender, _amountOfToken, totalEarned);

        adjustTokenPrice();
        console.log("price after selling", tokenPrice);
        emit TokenPriceUpdated(tokenPrice);
    }

    // Owner can withdraw excess tokens from the contract
    function withdrawTokens(uint256 _amount) public onlyOwner nonReentrant{
        require(_amount > 0, "Amount must be greater than 0");
        imlToken.safeTransfer(owner(), _amount);
        emit TokensWithdrawn(owner(), _amount);
    }

    // Owner can withdraw accumulated Ether from the contract
    function withdrawEther(uint256 _amount) public onlyOwner nonReentrant{
        require(_amount > 0, "Amount must be greater than 0");
        require(
            address(this).balance >= _amount,
            "Insufficient Ether in contract"
        );
        payable(owner()).transfer(_amount);
        emit EtherWithdrawn(owner(), _amount);
    }
}

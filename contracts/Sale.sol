// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./LidyERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";


contract Sale {
    uint256 public endTime;
    uint256 public startTime;
    uint public maxBid;
    address public maxBidder;
    address public creator;
    address public lidyverse = 0x64e48117560AE2b0b01AdaD0C5c84f029401a030;
    bytes32 public merkleRoot;
    Bid[] public bids;
    uint public tokenId;
    bool public isCancelled;
    bool public isNftWithdrawn = false;
    bool public areFundsWithdrawn = false;
    bool public isDirectBuy;
    uint public minIncrement;
    uint public directBuyPrice;
    uint public startPrice;
    address public nftAddress;
    uint public saleType;
    bool public whitelistSale;
    uint256 private lidyverseShare = 2;
    IERC721 _nft;

    event NewBid(address bidder, uint bid);
    event WithdrawNFT(address withdrawer);
    event WithdrawFunds(address withdrawer, uint256 amount);
    event SaleCanceled();
    event Refund(address refundee, uint256 amount);


    mapping(address => uint) public refunds;


    enum SaleState {
        OPEN,
        CANCELLED,
        ENDED,
        DIRECT_BUY,
        NOT_STARTED
    }

    struct Bid {
        address sender;
        uint256 bid;
    }

    constructor(address _creator, uint _startTime, uint _endTime ,uint _minIncrement,uint _directBuyPrice, uint _startPrice,address _nftAddress,uint _tokenId,uint _saleType, bool whitelistSale_)
    payable
    {
        creator = _creator;
        endTime = _endTime;
        startTime = _startTime;
        minIncrement = _minIncrement;
        directBuyPrice = _directBuyPrice;
        startPrice = _startPrice;
        _nft = IERC721(_nftAddress);
        nftAddress = _nftAddress;
        tokenId = _tokenId;
        maxBidder = _creator;
        saleType = _saleType;
	    whitelistSale = whitelistSale_;
    }

    
    function allBids()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory addrs = new address[](bids.length);
        uint256[] memory bidPrice = new uint256[](bids.length);
        for (uint256 i = 0; i < bids.length; i++) {
            addrs[i] = bids[i].sender;
            bidPrice[i] = bids[i].bid;
        }
        return (addrs, bidPrice);
    }

    function buyNow() payable external returns(bool){
        require(msg.sender != creator, "Sender is not the creator.");
        require(getSaleState() == SaleState.OPEN, "Sale is not open yet!");
        require(msg.value >= directBuyPrice, "Value is less than buy price.");
        require(isNftWithdrawn==false, "Nft is already withdrawn");

        address lastHightestBidder = maxBidder;
        uint256 lastHighestBid = maxBid;

        maxBid = msg.value;
        maxBidder = msg.sender;
        isDirectBuy = true;

        bids.push(Bid(msg.sender,msg.value));

        if(lastHighestBid != 0){
            refunds[lastHightestBidder]=lastHighestBid;
        }

        emit NewBid(msg.sender,msg.value);
        _nft.transferFrom(address(this), msg.sender, tokenId);
        isNftWithdrawn=true;
        emit WithdrawNFT(msg.sender);

        return true;
    }
    


    function placeBid() payable external returns(bool){
        require(msg.sender != creator);
        require(getSaleState() == SaleState.OPEN);
        require(msg.value >= startPrice);

        uint256 bidValue = refunds[msg.sender]+msg.value;

        if(saleType == 1){
            require(bidValue > maxBid + minIncrement);
        }

        address lastHightestBidder = maxBidder;
        uint256 lastHighestBid = maxBid;

        maxBid = refunds[msg.sender]+msg.value;
        maxBidder = msg.sender;

        if(msg.value >= directBuyPrice){
            isDirectBuy = true;
        }
        bids.push(Bid(msg.sender, maxBid));

        if(lastHighestBid != 0){
            refunds[lastHightestBidder] = lastHighestBid;
        }

        emit NewBid(msg.sender,msg.value);

        return true;
    }


    function withdrawNFT() external returns(bool){
        require(getSaleState() == SaleState.ENDED || getSaleState() == SaleState.DIRECT_BUY);
        require(msg.sender == maxBidder);
        require(isNftWithdrawn==false, "Nft is already withdrawn");
        _nft.transferFrom(address(this), maxBidder, tokenId);
        isNftWithdrawn=true;
        emit WithdrawNFT(maxBidder);
        return true;
    }

    function getRefund() external returns(bool){
        require(msg.sender != maxBidder);
        uint256 balance = refunds[msg.sender];
        require(balance > 0);
        refunds[msg.sender] = 0;
        payable(msg.sender).transfer(balance);
        emit Refund(msg.sender,balance);
        return true;
    }


    function withdrawFunds() external returns(bool){
        require(getSaleState() == SaleState.ENDED || getSaleState() == SaleState.DIRECT_BUY, "Sale has not finished yet.");
        require(msg.sender == creator, "Address is not the seller's.");
        require(areFundsWithdrawn==false,"Funds are already withdrawn");
        (address receiver_, uint256 royaltyAmount) = IERC2981(nftAddress).royaltyInfo(tokenId,maxBid);
        uint256 mgshare = (maxBid * lidyverseShare) / 100;
        uint256 creatorShare = maxBid - (royaltyAmount + mgshare);

        payable(receiver_).transfer(royaltyAmount);
        payable(creator).transfer(creatorShare);
        payable(lidyverse).transfer(mgshare);
        
        areFundsWithdrawn=true;
        emit WithdrawFunds(msg.sender,maxBid);
        return true;
    }


    function cancelSale() external returns(bool){
        require(msg.sender == creator);
        require(getSaleState() == SaleState.OPEN ||getSaleState() == SaleState.NOT_STARTED);
        require(maxBid == 0);
        isCancelled = true;
        _nft.transferFrom(address(this), creator, tokenId);
        emit SaleCanceled();
        return true;
    }


    function getSaleState() public view returns(SaleState) {
        if(isCancelled) return SaleState.CANCELLED;
        if(isDirectBuy) return SaleState.DIRECT_BUY;
        if(block.timestamp < startTime) return SaleState.NOT_STARTED;
        if(block.timestamp >= endTime) return SaleState.ENDED;
        return SaleState.OPEN;
    }

  
}

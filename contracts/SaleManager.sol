// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Sale.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract SaleManager is ReentrancyGuard, Ownable {

    event SaleCreated(
        uint indexed listingId,
        address saleAddress,
        address nftContract,
        uint256 tokenId,
        uint256 saleType
    );

    uint listingIdCounter; // unique & incremental id of listings
    bytes32 public merkleRoot;

    mapping(uint => address) public listings; // mapping from listingId to auction contract
    mapping(address => mapping(uint256 => address)) public listingsIndexed; // mapping from NFT contract adress and token ID to auction contract address

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }
    
    function getOwner(address _nftAddress,uint _tokenId) external view returns (address){
        IERC721 _nftToken = IERC721(_nftAddress);
        return _nftToken.ownerOf(_tokenId);
    }

    function getApproved(address _nftAddress,uint _tokenId) external view returns (address){
        IERC721 _nftToken = IERC721(_nftAddress);
        return _nftToken.getApproved(_tokenId);
    }

     function approveToken(address _nftAddress,uint _tokenId) external {
        IERC721 _nftToken = IERC721(_nftAddress);
        _nftToken.approve(address(this), _tokenId);
    }
    
    /// @param _saleType = 1 for auction, = 0 for direct sale
    /// @param _duration is in minutes
    function createListing(uint _duration, uint _minIncrement, uint _directBuyPrice,uint _startPrice,address _nftAddress,uint _tokenId,uint _saleType, bool whitelistSale, bytes32[] calldata proof)  external nonReentrant payable returns (bool) {
        require(_directBuyPrice > 0); 
        require(_duration > 3600); // lower boundry for sale duration
        require(MerkleProof.verify(proof, merkleRoot, keccak256(abi.encodePacked(msg.sender))), "You are not allowed to list!");

        IERC721 _nftToken = IERC721(_nftAddress);
        require(_nftToken.ownerOf(_tokenId)==msg.sender,"not owner of nft");
        uint listingId = listingIdCounter;  
        Sale sale = new Sale(msg.sender, _duration*60, _minIncrement, _directBuyPrice, _startPrice, _nftAddress, _tokenId, _saleType, whitelistSale); // deploy new auction contract 
        _nftToken.transferFrom(msg.sender, address(sale), _tokenId); //transfer NFT to auction contract
        listings[listingId] = address(sale);  // sale contract mapped to listing Id
        listingsIndexed[_nftAddress][_tokenId] = address(sale); // sale contract mapped to nft address and token id
        emit SaleCreated(listingId,address(sale),_nftAddress,_tokenId,_saleType); 
        listingIdCounter++; // increment listingIdCounter
        return true;
    }
    
    function getListings() external view returns(address[] memory _listings) {
        _listings = new address[](listingIdCounter); 
        for(uint i = 0; i < listingIdCounter; i++) {
            _listings[i] = listings[i];
        }
        // listing mapping converted to array
        return _listings; 
    }
    

    function getListingFromNFT(address nftContractAddress, uint256 tokenId_) external view  returns(address){
        return listingsIndexed[nftContractAddress][tokenId_];
    }

    function getNFTfromListing(address listingAddress_) external view returns(address,uint256){
        address nftAddress = Sale(listingAddress_).nftAddress();
        uint256 tokenId = Sale(listingAddress_).tokenId();
        return (nftAddress,tokenId);
    }   

    function getListingInfo(address  _auctionAddr)
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {

            address maxBidder = Sale(_auctionAddr).maxBidder(); 
            uint256 highestBid = Sale(_auctionAddr).maxBid(); 
            uint256 startPrice = Sale(_auctionAddr).startPrice();
            uint256 directBuy = Sale(_auctionAddr).directBuyPrice(); 
            uint256 endTime = Sale(_auctionAddr).endTime(); 
            uint256 saleState = uint(Sale(_auctionAddr).getSaleState()); 
            // nft address and token id returns deleted due to solidity's limitation
        return ( 
            maxBidder,
            highestBid,
            startPrice,
            directBuy,
            endTime,
            saleState
        );
    }

}

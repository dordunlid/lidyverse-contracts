//SPDX-License-Identifier: MIT

/*
LIDYVERSE - 2022
*/

pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";



contract LidyNFT is  Ownable, ERC2981, ERC721Enumerable {

  using Strings for uint256;
  using Counters for Counters.Counter;

  Counters.Counter private supply;

  mapping (address => uint) private nftHolders;
  
  bytes32 public merkleRoot;
  
  string public ipfsURI; 

  uint256  public whitelistPrice = 0.03 ether; 
  uint256  public publicPrice = 0.03 ether; 
  uint256  public maxSupply = 1000; 
  uint256  public maxMintPerWallet = 6; 

  bool public paused = false;
  bool public whitelistMintable = false;
  bool public publicMintable = false;

  constructor(        
        string memory uri_,
        address _royaltyRecipient,
        uint96 _royaltyValue) ERC721("LidyNFT", "LIDY") {
        _setDefaultRoyalty(_royaltyRecipient,_royaltyValue);
        ipfsURI = uri_;
    
  }

  function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

  function whitelistMint(uint256 mintAmount_, bytes32[] calldata proof) external payable {
    require(paused == false, "Minting is not active!");
    require(whitelistMintable, "Whitelist minting is not started!");
    require(supply.current() + mintAmount_ <= maxSupply, "Max supply exceeded!");
    require(nftHolders[msg.sender] + mintAmount_ <= maxMintPerWallet, "Mint limit");
    require(MerkleProof.verify(proof, merkleRoot, keccak256(abi.encodePacked(msg.sender))), "You are not whitelisted!");
    require(msg.value >= whitelistPrice * mintAmount_, "Insufficient funds!");
    
    nftHolders[msg.sender] += mintAmount_;
    _mintLoop(msg.sender, mintAmount_);
    
  }

  function publicMint(uint256 mintAmount_) external payable  {
     require(paused == false, "Minting is not active!");
     require(publicMintable, "Public mint is not started!");
     require(supply.current() + mintAmount_ <= maxSupply, "Max supply exceeded!");
     require(msg.value >= publicPrice * mintAmount_, "Insufficient funds!");
     
     nftHolders[msg.sender] += mintAmount_;
    _mintLoop(msg.sender, mintAmount_);
  }

  function _mintLoop(address walletToMint_, uint256 mintAmount_) internal {
    for (uint256 i = 0; i < mintAmount_; i++) {
      supply.increment();
      _safeMint(walletToMint_, supply.current());
    }
  }

  function setWhitelistPrice(uint256 wlPrice_) external onlyOwner {
    whitelistPrice = wlPrice_;
  }
  
  function setPublicPrice(uint256 publicPrice_) external onlyOwner {
    publicPrice = publicPrice_;
  }

  function setMaxSupply(uint256 maxSupply_) external onlyOwner {
    maxSupply = maxSupply_;
  }

  function setWhitelistMintable(bool _state) external onlyOwner {
    whitelistMintable = _state;
  }

  function setPublicMintable(bool _state) external onlyOwner {
    publicMintable = _state;
  }
  
  function pause() external onlyOwner {
    paused = true;
  }

  function unpause() external onlyOwner {
    paused = false;
  }

  function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
    require(_exists(_tokenId), "This nft does not exist!");

    string memory currentBaseURI = _baseURI();
    return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), ".json"))
        : "";
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return ipfsURI;
  }

  function currentSupply() external view returns (uint256) {
    return supply.current();
  }

  function setIpfsURI(string memory _ipfsURI) external onlyOwner {
    ipfsURI = _ipfsURI;
  }

  function setDefaultRoyalty(address receiver_, uint96 fee_) external onlyOwner {
    _setDefaultRoyalty(receiver_,fee_);
  }


  function withdraw() external onlyOwner {
    _withdraw(owner(), address(this).balance);
  }

  function _withdraw(address _address, uint256 _amount) private {
    (bool success, ) = _address.call{value: _amount}("");
    require(success, "Transfer failed.");
  }

  function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable, ERC2981) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

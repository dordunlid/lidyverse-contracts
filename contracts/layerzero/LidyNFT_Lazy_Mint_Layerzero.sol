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
import "./NonBlockingReceiver.sol";
import "./interfaces/ILayerZeroEndpoint.sol";





contract LidyNFT is  Ownable, ERC2981, ERC721Enumerable, ILayerZeroUserApplicationConfig, NonblockingReceiver{

  using Strings for uint256;
  using Counters for Counters.Counter;


  Counters.Counter private supply;

  mapping (address => uint) private nftHolders;
  
  bytes32 public merkleRoot;
  
  string public ipfsURI; 

  uint256 public gasForDestinationLzReceive = 350000;
  uint256  public whitelistPrice = 0.03 ether; 
  uint256  public publicPrice = 0.03 ether; 
  uint256  public maxSupply = 1000; 
  uint256  public maxMintPerWallet = 6; 

  bool public paused = false;
  bool public whitelistMintable = false;
  bool public publicMintable = false;

  constructor(        
        string memory uri_,
        address _layerZeroEndpoint,
        address _royaltyRecipient,
        uint96 _royaltyValue) ERC721("LidyNFT", "LIDY") {
        endpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
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

  function burn(uint256 tokenId) external {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner nor approved");
        _burn(tokenId);
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

  function traverseChains(
        uint16 _chainId,
        uint256 _tokenId
    ) public payable {
        require(msg.sender == ownerOf(_tokenId), "Message sender must own the NFT.");
        require(trustedSourceLookup[_chainId].length != 0, "This chain is not a trusted source source.");

        // burn NFT on source chain
         _burn(_tokenId);

        // encode payload w/ sender address and NFT token id
        bytes memory payload = abi.encode(msg.sender, _tokenId);

        // encode adapterParams w/ extra gas for destination chain
        uint16 version = 1;
        uint gas = gasForDestinationLzReceive;
        bytes memory adapterParams = abi.encodePacked(version, gas);

        // use LayerZero estimateFees for cross chain delivery
        (uint quotedLayerZeroFee, ) = endpoint.estimateFees(_chainId, address(this), payload, false, adapterParams);

        require(msg.value >= quotedLayerZeroFee, "Not enough gas to cover cross chain transfer.");

        endpoint.send{value:msg.value}(
            _chainId,                      // destination chainId
            trustedSourceLookup[_chainId], // destination address of nft
            payload,                       // abi.encode()'ed bytes
            payable(msg.sender),           // refund address
            address(0x0),                  // future parameter
            adapterParams                  // adapterParams
        );
    }

    // just in case this fixed variable limits us from future integrations
    function setGasForDestinationLzReceive(uint256 newVal) external onlyOwner {
        gasForDestinationLzReceive = newVal;
    }

    /// @notice Override the _LzReceive internal function of the NonblockingReceiver
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent
    function _LzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) internal override  {
        (address dstAddress, uint256 tokenId) = abi.decode(_payload, (address, uint256));
        _safeMint(dstAddress, tokenId);
    }

    // User Application Config
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint256 _configType,
        bytes calldata _config
    ) external override onlyOwner {
        endpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function setSendVersion(uint16 _version) external override onlyOwner {
        endpoint.setSendVersion(_version);
    }

    function setReceiveVersion(uint16 _version) external override onlyOwner {
        endpoint.setReceiveVersion(_version);
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyOwner {
        endpoint.forceResumeReceive(_srcChainId, _srcAddress);
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

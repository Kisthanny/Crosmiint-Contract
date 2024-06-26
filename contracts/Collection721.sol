// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Collection721 is ERC721, ERC721URIStorage, Ownable {
    using Strings for uint256;

    uint256 private _nextTokenId;
    string public baseURI;
    string public logoURI;
    bool private _baseURISet;

    struct Drop {
        uint256 supply;
        uint256 minted;
        uint256 mintLimitPerWallet;
        uint256 startTime;
        uint256 endTime;
        bool hasWhiteListPhase;
        uint256 whiteListEndTime;
        mapping(address => bool) whiteListAddresses;
        mapping(address => uint256) mintedPerWallet;
    }

    Drop public currentDrop;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _logoURI
    ) ERC721(_name, _symbol) Ownable(msg.sender) {
        logoURI = _logoURI;
    }

    modifier onlyDuringDrop() {
        require(
            block.timestamp >= currentDrop.startTime &&
                block.timestamp <= currentDrop.endTime,
            "Drop not active"
        );
        _;
    }

    modifier onlyAfterDrop() {
        require(
            currentDrop.endTime != 0 && block.timestamp >= currentDrop.endTime,
            "Drop not end or no initial Drop"
        );
        _;
    }

    modifier canMint(uint256 amount) {
        require(
            currentDrop.mintedPerWallet[msg.sender] + amount <=
                currentDrop.mintLimitPerWallet,
            "Mint limit per wallet exceeded"
        );
        require(
            currentDrop.minted + amount <= currentDrop.supply,
            "Exceeds drop supply"
        );
        _;
    }

    modifier beforeUpload() {
        require(!_baseURISet, "Cannot proceed after upload");
        _;
    }

    function getWhiteListAccess(
        address _userAddress
    ) public view returns (bool) {
        return currentDrop.whiteListAddresses[_userAddress];
    }

    function getMintCount(address _userAddress) public view returns (uint256) {
        return currentDrop.mintedPerWallet[_userAddress];
    }

    function setBaseURI(
        string memory _baseURI
    ) public onlyOwner beforeUpload onlyAfterDrop {
        baseURI = _baseURI;
        _baseURISet = true;
    }

    function setLogoURI(string memory _logoURI) public onlyOwner {
        logoURI = _logoURI;
    }

    // for user
    // they mint during drop
    // tokenURI will be set by owner after drop ends
    function safeMint(uint256 amount) public onlyDuringDrop canMint(amount) {
        // check whiteList access during whiteList phase
        if (
            currentDrop.hasWhiteListPhase &&
            block.timestamp <= currentDrop.whiteListEndTime
        ) {
            require(
                currentDrop.whiteListAddresses[msg.sender],
                "Only whitelist address can mint during whitelist phase."
            );
        }
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(msg.sender, tokenId);
        }
        currentDrop.minted += amount;
        currentDrop.mintedPerWallet[msg.sender] += amount;
    }

    function createDrop(
        uint256 _supply,
        uint256 _mintLimitPerWallet,
        uint256 _startTime,
        uint256 _endTime,
        bool _hasWhiteListPhase,
        uint256 _whiteListEndTime,
        address[] memory _whiteListAddresses
    ) external onlyOwner beforeUpload {
        require(block.timestamp > currentDrop.endTime, "Ongoing drop exists");

        currentDrop.supply = _supply;
        currentDrop.minted = 0;
        currentDrop.mintLimitPerWallet = _mintLimitPerWallet;
        currentDrop.startTime = _startTime;
        currentDrop.endTime = _endTime;
        currentDrop.hasWhiteListPhase = _hasWhiteListPhase;
        currentDrop.whiteListEndTime = _whiteListEndTime;

        // 设置白名单地址
        for (uint256 i = 0; i < _whiteListAddresses.length; i++) {
            currentDrop.whiteListAddresses[_whiteListAddresses[i]] = true;
        }
    }

    // 重写tokenURI方法
    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        require(
            _ownerOf(tokenId) != address(0),
            "ERC721Metadata: URI query for nonexistent token"
        );

        require(_baseURISet, "Not revealed yet");

        return
            string(abi.encodePacked(baseURI, "/metadata/", tokenId.toString()));
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

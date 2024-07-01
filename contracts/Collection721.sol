// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Collection721 is ERC721, ERC721URIStorage, ERC721Burnable, Ownable {
    using Strings for uint256;

    uint256 private _nextTokenId;
    uint16 private _nextDropId;
    string public baseURI;
    string public logoURI;
    bool private _baseURISet;

    struct Drop {
        uint256 supply;
        uint256 minted;
        uint256 mintLimitPerWallet;
        uint256 startTime;
        uint256 endTime;
        uint256 price;
        bool hasWhiteListPhase;
        uint256 whiteListEndTime;
        uint256 whiteListPrice;
        mapping(address => bool) whiteListAddresses;
        mapping(address => uint256) mintedPerWallet;
    }

    struct DropReturn {
        uint256 supply;
        uint256 minted;
        uint256 mintLimitPerWallet;
        uint256 startTime;
        uint256 endTime;
        uint256 price;
        bool hasWhiteListPhase;
        uint256 whiteListEndTime;
        uint256 whiteListPrice;
    }

    mapping(uint16 => Drop) private DropList;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _logoURI
    ) ERC721(_name, _symbol) Ownable(msg.sender) {
        logoURI = _logoURI;
    }

    modifier onlyDuringDrop() {
        Drop storage drop = DropList[_nextDropId];
        require(
            block.timestamp >= drop.startTime &&
                block.timestamp <= drop.endTime,
            "Drop not active"
        );
        _;
    }

    modifier onlyAfterDrop() {
        Drop storage drop = DropList[_nextDropId];
        require(
            drop.endTime != 0 && block.timestamp > drop.endTime,
            "Drop not end or no initial Drop"
        );
        _;
    }

    modifier canMint(uint256 amount) {
        Drop storage drop = DropList[_nextDropId];
        require(
            drop.mintedPerWallet[msg.sender] + amount <=
                drop.mintLimitPerWallet,
            "Mint limit per wallet exceeded"
        );
        require(drop.minted + amount <= drop.supply, "Exceeds drop supply");
        _;
    }

    modifier beforeUpload() {
        require(!_baseURISet, "Cannot proceed after upload");
        _;
    }

    function currentDrop() public view returns (DropReturn memory) {
        Drop storage drop = DropList[_nextDropId];
        DropReturn memory dropReturn = DropReturn(
            drop.supply,
            drop.minted,
            drop.mintLimitPerWallet,
            drop.startTime,
            drop.endTime,
            drop.price,
            drop.hasWhiteListPhase,
            drop.whiteListEndTime,
            drop.whiteListPrice
        );
        return dropReturn;
    }

    function getWhiteListAccess(
        address _userAddress
    ) public view returns (bool) {
        Drop storage drop = DropList[_nextDropId];
        return drop.whiteListAddresses[_userAddress];
    }

    function getMintCount(address _userAddress) public view returns (uint256) {
        Drop storage drop = DropList[_nextDropId];
        return drop.mintedPerWallet[_userAddress];
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

    function safeMint(
        uint256 amount
    ) public payable onlyDuringDrop canMint(amount) {
        Drop storage drop = DropList[_nextDropId];
        uint256 pricePerToken = drop.price;
        if (
            drop.hasWhiteListPhase && block.timestamp <= drop.whiteListEndTime
        ) {
            require(
                drop.whiteListAddresses[msg.sender],
                "Only whitelist address can mint during whitelist phase."
            );
            pricePerToken = drop.whiteListPrice;
        }
        require(
            pricePerToken * amount == msg.value,
            "Please set the right value for minting"
        );

        payable(owner()).transfer(msg.value);

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(msg.sender, tokenId);
        }
        drop.minted += amount;
        drop.mintedPerWallet[msg.sender] += amount;
    }

    function createDrop(
        uint256 _supply,
        uint256 _mintLimitPerWallet,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _price,
        bool _hasWhiteListPhase,
        uint256 _whiteListEndTime,
        uint256 _whiteListPrice,
        address[] memory _whiteListAddresses
    ) external onlyOwner beforeUpload {
        Drop storage drop = DropList[_nextDropId];
        require(block.timestamp > drop.endTime, "Ongoing drop exists");

        _nextDropId++;

        Drop storage newDrop = DropList[_nextDropId];

        newDrop.supply = _supply;
        newDrop.minted = 0;
        newDrop.mintLimitPerWallet = _mintLimitPerWallet;
        newDrop.startTime = _startTime;
        newDrop.endTime = _endTime;
        newDrop.price = _price;
        newDrop.hasWhiteListPhase = _hasWhiteListPhase;
        newDrop.whiteListEndTime = _whiteListEndTime;
        newDrop.whiteListPrice = _whiteListPrice;

        for (uint256 i = 0; i < _whiteListAddresses.length; i++) {
            newDrop.whiteListAddresses[_whiteListAddresses[i]] = true;
        }
    }

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

// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./IGmpReceiver.sol";
import "./IGateway.sol";

contract Collection721 is
    ERC721,
    ERC721URIStorage,
    ERC721Burnable,
    Ownable,
    IGmpReceiver
{
    using Strings for uint256;

    address public immutable _gateway;
    uint256 private _nextTokenId;
    uint16 private _nextDropId;
    string public baseURI;
    string public logoURI;
    bool private _baseURISet;
    bool public isBase;

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
        uint16 dropId;
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

    struct CrosschainMessage {
        uint256 tokenId;
        address newHolder;
    }

    event TokenMinted(uint256 tokenId, uint256 amount, address indexed minter, bool isFromDrop);
    event DropCreated(
        uint16 dropId,
        uint256 supply,
        uint256 mintLimitPerWallet,
        uint256 startTime,
        uint256 endTime,
        uint256 price,
        bool hasWhiteListPhase,
        uint256 whiteListEndTime,
        uint256 whiteListPrice
    );
    event BaseURISet(string baseURI);
    event LogoURISet(string logoURI);
    event TokenBurned(uint256 tokenId, address indexed burner);
    event CrosschainTransferInitiated(
        uint256 tokenId,
        address indexed newHolder,
        uint16 destinationNetwork,
        address indexed initiator
    );
    event CrosschainAddressSet(uint16 network, address contractAddress);
    event WhiteListAddressSet(uint16 dropId, address indexed userAddress);

    mapping(uint16 => Drop) private DropList;
    mapping(uint256 => address) private _burntBy;
    mapping(uint16 => address) private _crosschainContract;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _logoURI,
        address gateway,
        bool _isBase
    ) ERC721(_name, _symbol) Ownable(msg.sender) {
        logoURI = _logoURI;
        _gateway = gateway;
        isBase = _isBase;
    }

    modifier onlyBase() {
        require(isBase, "Only Base contract could call this function");
        _;
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

    function setCrosschainAddress(
        uint16 _network,
        address _contractAddress
    ) public onlyOwner {
        require(
            _crosschainContract[_network] == address(0),
            "crossChain contract already exist"
        );
        _crosschainContract[_network] = _contractAddress;
        emit CrosschainAddressSet(_network, _contractAddress);
    }

    // assuming the gateway already handles verification
    // we just need to mint on received
    function onGmpReceived(
        bytes32,
        uint128,
        bytes32,
        bytes calldata b
    ) external payable returns (bytes32) {
        require(msg.sender == _gateway, "unauthorized");
        CrosschainMessage memory message = abi.decode(b, (CrosschainMessage));
        _safeMint(message.newHolder, message.tokenId);
        _burntBy[message.tokenId] = address(0);

        emit TokenMinted(message.tokenId, 1, message.newHolder, false);

        return bytes32("");
    }

    function encodeCrosschainMessage(
        uint256 _tokenId,
        address _newHolder
    ) public pure returns (bytes memory) {
        CrosschainMessage memory message = CrosschainMessage(
            _tokenId,
            _newHolder
        );
        return abi.encode(message);
    }

    function crosschainTransfer(
        uint256 _tokenId,
        address _newHolder,
        uint16 _destinationNetwork
    ) public {
        require(
            _crosschainContract[_destinationNetwork] != address(0),
            "Crosschain: Unsupport Network"
        );
        require(
            _ownerOf(_tokenId) == msg.sender,
            "Crosschain: Token is not owned by Sender"
        );
        burn(_tokenId);
        IGateway gateway = IGateway(_gateway);
        gateway.submitMessage(
            _crosschainContract[_destinationNetwork],
            _destinationNetwork,
            3000000,
            encodeCrosschainMessage(_tokenId, _newHolder)
        );

        emit CrosschainTransferInitiated(
            _tokenId,
            _newHolder,
            _destinationNetwork,
            msg.sender
        );
    }

    function currentDrop() public view onlyBase returns (DropReturn memory) {
        Drop storage drop = DropList[_nextDropId];
        DropReturn memory dropReturn = DropReturn(
            _nextDropId,
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

    function burn(uint256 _tokenId) public override {
        super.burn(_tokenId);
        _burntBy[_tokenId] = msg.sender;

        emit TokenBurned(_tokenId, msg.sender);
    }

    function burntBy(uint256 _tokenId) public view returns (address) {
        return _burntBy[_tokenId];
    }

    function getWhiteListAccess(
        address _userAddress
    ) public view onlyBase returns (bool) {
        Drop storage drop = DropList[_nextDropId];
        return drop.whiteListAddresses[_userAddress];
    }

    function getMintCount(
        address _userAddress
    ) public view onlyBase returns (uint256) {
        Drop storage drop = DropList[_nextDropId];
        return drop.mintedPerWallet[_userAddress];
    }

    function setBaseURI(
        string memory _baseURI
    ) public onlyOwner beforeUpload onlyAfterDrop onlyBase {
        baseURI = _baseURI;
        _baseURISet = true;

        emit BaseURISet(_baseURI);
    }

    function setLogoURI(string memory _logoURI) public onlyOwner onlyBase {
        logoURI = _logoURI;

        emit LogoURISet(_logoURI);
    }

    function safeMint(
        uint256 amount
    ) public payable onlyDuringDrop canMint(amount) onlyBase {
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

        emit TokenMinted(_nextTokenId - amount, amount, msg.sender, true);
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
    ) external onlyOwner beforeUpload onlyBase {
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
            emit WhiteListAddressSet(_nextDropId, _whiteListAddresses[i]);
        }

        emit DropCreated(
            _nextDropId,
            _supply,
            _mintLimitPerWallet,
            _startTime,
            _endTime,
            _price,
            _hasWhiteListPhase,
            _whiteListEndTime,
            _whiteListPrice
        );
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

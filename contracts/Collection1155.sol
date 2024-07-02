// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./IGmpReceiver.sol";
import "./IGateway.sol";

contract Collection1155 is ERC1155, Ownable, IGmpReceiver {
    using Strings for uint256;

    address public immutable _gateway;
    string public name;
    string public symbol;
    string public logoURI;
    uint256 private _nextTokenId;

    struct CrosschainMessage {
        uint256 tokenId;
        string tokenURI;
        address newHolder;
        uint256 amount;
    }

    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => uint256) private _totalSupply;
    mapping(uint16 => address) private _crosschainContract;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _logoURI,
        address gateway
    ) ERC1155("") Ownable(msg.sender) {
        name = _name;
        symbol = _symbol;
        logoURI = _logoURI;
        _gateway = gateway;
    }

    // asuming the gateway already handles verification
    // we just need to mint on received
    function onGmpReceived(
        bytes32,
        uint128,
        bytes32,
        bytes calldata b
    ) external payable returns (bytes32) {
        require(msg.sender == _gateway, "unauthorized");
        CrosschainMessage memory message = abi.decode(b, (CrosschainMessage));
        mintByGateway(
            message.tokenId,
            message.newHolder,
            message.amount,
            message.tokenURI
        );
        return bytes32("");
    }

    function crosschainTransfer(
        uint256 _tokenId,
        string calldata _tokenURI,
        address _newHolder,
        uint256 _amount,
        uint16 _destinationNetwork
    ) public {
        require(
            _crosschainContract[_destinationNetwork] != address(0),
            "Crosschain: Unsupport Network"
        );
        require(
            balanceOf(msg.sender, _tokenId) >= _amount,
            "Crosschain: Insufficient amount owned by Sender"
        );
        burn(msg.sender, _tokenId, _amount);
        IGateway gateway = IGateway(_gateway);
        gateway.submitMessage(
            _crosschainContract[_destinationNetwork],
            _destinationNetwork,
            3000000,
            encodeCrosschainMessage(_tokenId, _tokenURI, _newHolder, _amount)
        );
    }

    function encodeCrosschainMessage(
        uint256 _tokenId,
        string memory _tokenURI,
        address _newHolder,
        uint256 _amount
    ) private pure returns (bytes memory) {
        CrosschainMessage memory message = CrosschainMessage(
            _tokenId,
            _tokenURI,
            _newHolder,
            _amount
        );
        return abi.encode(message);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return _tokenURIs[tokenId];
    }

    function mint(
        uint256 amount,
        string memory metadataURI,
        bytes memory data
    ) public onlyOwner {
        _mint(msg.sender, _nextTokenId, amount, data);
        _setTokenURI(_nextTokenId, metadataURI);
        _totalSupply[_nextTokenId] += amount;
        _nextTokenId++;
    }

    function mintByGateway(
        uint256 tokenId,
        address holder,
        uint256 amount,
        string memory metadataURI
    ) private {
        require(msg.sender == _gateway, "unauthorized");
        _mint(holder, tokenId, amount, "");
        _setTokenURI(tokenId, metadataURI);
        _totalSupply[tokenId] += amount;
    }

    function mintBatch(
        uint256[] memory amounts,
        string[] memory metadataURIs,
        bytes memory data
    ) public onlyOwner {
        require(
            amounts.length == metadataURIs.length,
            "Amounts and metadataURIs length mismatch"
        );

        uint256[] memory ids = new uint256[](amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            ids[i] = _nextTokenId;
            _setTokenURI(_nextTokenId, metadataURIs[i]);
            _totalSupply[_nextTokenId] += amounts[i];
            _nextTokenId++;
        }

        _mintBatch(msg.sender, ids, amounts, data);
    }

    function burn(address account, uint256 id, uint256 amount) public {
        require(
            balanceOf(account, id) >= amount,
            "Burn: caller insufficient amount"
        );
        _burn(account, id, amount);
        _totalSupply[id] -= amount;
    }

    function burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory amounts
    ) public {
        require(ids.length == amounts.length);
        for (uint256 i = 0; i < ids.length; i++) {
            burn(account, ids[i], amounts[i]);
            _totalSupply[ids[i]] -= amounts[i];
        }
    }

    function _setTokenURI(uint256 tokenId, string memory metadataURI) internal {
        _tokenURIs[tokenId] = metadataURI;
    }

    function totalSupply(uint256 tokenId) public view returns (uint256) {
        return _totalSupply[tokenId];
    }
}

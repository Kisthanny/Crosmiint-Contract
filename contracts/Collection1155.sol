// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Collection1155 is ERC1155, Ownable {
    using Strings for uint256;

    string public name;
    string public symbol;
    string public logoURI;
    uint256 private _nextTokenId;
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => uint256) private _totalSupply;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _logoURI
    ) ERC1155("") Ownable(msg.sender) {
        name = _name;
        symbol = _symbol;
        logoURI = _logoURI;
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

    function _setTokenURI(uint256 tokenId, string memory metadataURI) internal {
        _tokenURIs[tokenId] = metadataURI;
    }

    function totalSupply(uint256 tokenId) public view returns (uint256) {
        return _totalSupply[tokenId];
    }
}

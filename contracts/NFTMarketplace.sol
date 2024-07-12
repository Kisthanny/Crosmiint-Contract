// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketplace is Ownable, ERC1155Holder, ERC721Holder {
    enum TokenType {
        ERC721,
        ERC1155
    }

    struct Listing {
        address seller;
        address contractAddress; // Address of the ERC721 or ERC1155 contract
        uint256 tokenId;
        uint256 amount; // For ERC1155, use 1 for ERC721
        uint256 price;
        TokenType tokenType;
        bool active;
    }

    struct Offer {
        address offerer;
        uint256 offerPrice;
        bool active;
    }

    mapping(uint256 => Listing) public listings;
    mapping(address => Listing[]) public activeListings; // Map to store active listings by contract address
    mapping(uint256 => Offer[]) public offers;
    uint256 public nextListingId;

    address public intermediary;
    uint256 public serviceFeePercent; // e.g., 100 = 1%

    event Listed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed contractAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        TokenType tokenType
    );
    event Cancelled(uint256 indexed listingId);
    event Bought(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 price
    );
    event OfferMade(
        uint256 indexed listingId,
        address indexed offerer,
        uint256 offerPrice,
        uint256 offerIndex
    );
    event OfferAccepted(
        uint256 indexed listingId,
        address indexed offerer,
        uint256 offerPrice,
        uint256 offerIndex
    );
    event OfferCancelled(
        uint256 indexed listingId,
        address indexed offerer,
        uint256 offerIndex
    );
    event IntermediaryChanged(address indexed newIntermediary);
    event ServiceFeePercentChanged(uint256 newServiceFeePercent);

    constructor() Ownable(msg.sender) {
        intermediary = msg.sender;
        serviceFeePercent = 100; // 1%
    }

    function setIntermediary(address newIntermediary) external onlyOwner {
        require(newIntermediary != address(0), "Invalid address");
        intermediary = newIntermediary;
        emit IntermediaryChanged(newIntermediary);
    }

    function setServiceFeePercent(
        uint256 newServiceFeePercent
    ) external onlyOwner {
        require(newServiceFeePercent <= 1000, "Fee percent too high"); // Max 10%
        serviceFeePercent = newServiceFeePercent;
        emit ServiceFeePercentChanged(newServiceFeePercent);
    }

    function listNFT(
        address contractAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        TokenType tokenType
    ) external {
        require(price > 0, "Price must be greater than zero");

        if (tokenType == TokenType.ERC721) {
            IERC721(contractAddress).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        } else {
            IERC1155(contractAddress).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId,
                amount,
                ""
            );
        }

        listings[nextListingId] = Listing({
            seller: msg.sender,
            contractAddress: contractAddress,
            tokenId: tokenId,
            amount: amount,
            price: price,
            tokenType: tokenType,
            active: true
        });

        activeListings[contractAddress].push(listings[nextListingId]); // Update active listings for contract address

        emit Listed(
            nextListingId,
            msg.sender,
            contractAddress,
            tokenId,
            amount,
            price,
            tokenType
        );
        nextListingId++;
    }

    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(
            listing.seller == msg.sender,
            "Only the seller can cancel the listing"
        );
        require(listing.active, "Listing is not active");

        address contractAddress = listing.contractAddress; // Store contract address in a local variable

        if (listing.tokenType == TokenType.ERC721) {
            IERC721(contractAddress).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId
            );
        } else {
            IERC1155(contractAddress).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId,
                listing.amount,
                ""
            );
        }

        listing.active = false;
        emit Cancelled(listingId);
    }

    function buyNFT(uint256 listingId) external payable {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing is not active");
        require(msg.value >= listing.price, "Insufficient payment");

        listing.active = false;

        uint256 serviceFee = (listing.price * serviceFeePercent) / 10000;
        uint256 sellerProceeds = listing.price - serviceFee;

        payable(listing.seller).transfer(sellerProceeds);
        payable(intermediary).transfer(serviceFee);

        if (listing.tokenType == TokenType.ERC721) {
            IERC721(listing.contractAddress).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId
            );
        } else {
            IERC1155(listing.contractAddress).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId,
                listing.amount,
                ""
            );
        }

        emit Bought(listingId, msg.sender, listing.price);
    }

    function makeOffer(uint256 listingId, uint256 offerPrice) external payable {
        require(msg.value == offerPrice, "Offer price must equal sent value");
        require(offerPrice > 0, "Offer price must be greater than zero");
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing is not active");

        offers[listingId].push(
            Offer({offerer: msg.sender, offerPrice: offerPrice, active: true})
        );

        emit OfferMade(
            listingId,
            msg.sender,
            offerPrice,
            offers[listingId].length - 1
        );
    }

    function getOffer(
        uint256 _listingId,
        uint256 _offerIndex
    ) public view returns (Offer memory) {
        return offers[_listingId][_offerIndex];
    }

    function acceptOffer(uint256 listingId, uint256 offerIndex) external {
        Listing storage listing = listings[listingId];
        require(
            listing.seller == msg.sender,
            "Only the seller can accept an offer"
        );
        require(listing.active, "Listing is not active");
        Offer storage offer = offers[listingId][offerIndex];
        require(offer.active, "Offer is not active");

        listing.active = false;
        offer.active = false;

        uint256 serviceFee = (offer.offerPrice * serviceFeePercent) / 10000;
        uint256 sellerProceeds = offer.offerPrice - serviceFee;

        payable(listing.seller).transfer(sellerProceeds);
        payable(intermediary).transfer(serviceFee);

        if (listing.tokenType == TokenType.ERC721) {
            IERC721(listing.contractAddress).safeTransferFrom(
                address(this),
                offer.offerer,
                listing.tokenId
            );
        } else {
            IERC1155(listing.contractAddress).safeTransferFrom(
                address(this),
                offer.offerer,
                listing.tokenId,
                listing.amount,
                ""
            );
        }

        emit OfferAccepted(
            listingId,
            offer.offerer,
            offer.offerPrice,
            offerIndex
        );
    }

    function cancelOffer(uint256 listingId, uint256 offerIndex) external {
        Offer storage offer = offers[listingId][offerIndex];
        require(
            offer.offerer == msg.sender,
            "Only the offerer can cancel the offer"
        );
        require(offer.active, "Offer is not active");

        offer.active = false;

        payable(offer.offerer).transfer(offer.offerPrice);

        emit OfferCancelled(listingId, msg.sender, offerIndex);
    }

    function getActiveListingsByContract(
        address contractAddress
    ) external view returns (Listing[] memory) {
        return activeListings[contractAddress];
    }
}

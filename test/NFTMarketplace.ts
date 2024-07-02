import { expect } from "chai";
import hre from "hardhat";
import { Collection721, Collection1155, NFTMarketplace } from "../typechain-types";
import { ContractTransactionResponse, ethers } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

const sleep = (timeout: number) => {
    return new Promise((resolve, reject) => {
        setTimeout(() => {
            resolve(null);
        }, timeout)
    })
}

const getBlockTime = async () => {
    const latestBlock = await hre.ethers.provider.getBlock("latest")
    if (latestBlock?.timestamp) {
        return latestBlock.timestamp;
    } else {
        throw new Error('error getting block timestamp')
    }
}

describe("NFTMarketplace", () => {
    let owner: HardhatEthersSigner;
    let user_1: HardhatEthersSigner;
    let user_2: HardhatEthersSigner;
    let user_3: HardhatEthersSigner;
    let collection721: Collection721 & {
        deploymentTransaction(): ContractTransactionResponse;
        getAddress(): Promise<string>;
    }
    let collection1155: Collection1155 & {
        deploymentTransaction(): ContractTransactionResponse;
        getAddress(): Promise<string>;
    }
    let marketplace: NFTMarketplace & {
        deploymentTransaction(): ContractTransactionResponse;
        getAddress(): Promise<string>;
    }
    const GATEWAY = "0x000000007f56768dE3133034FA730a909003a165";

    beforeEach(async () => {
        // set up signers
        [owner, user_1, user_2, user_3] = await hre.ethers.getSigners();

        // deploy Collection721 contract
        const Collection721Factory = await hre.ethers.getContractFactory("Collection721");
        collection721 = await Collection721Factory.connect(owner).deploy("Collection721", "C721", "", GATEWAY) as Collection721 & {
            deploymentTransaction(): ContractTransactionResponse;
            getAddress(): Promise<string>;
        };

        // deploy Collection1155 contract
        const Collection1155Factory = await hre.ethers.getContractFactory("Collection1155");
        collection1155 = await Collection1155Factory.connect(owner).deploy("Collection1155", "C1155", "", GATEWAY) as Collection1155 & {
            deploymentTransaction(): ContractTransactionResponse;
            getAddress(): Promise<string>;
        };

        // deploy NFTMarketplace contract
        const NFTMarketplaceFactory = await hre.ethers.getContractFactory("NFTMarketplace");
        marketplace = await NFTMarketplaceFactory.connect(owner).deploy() as NFTMarketplace & {
            deploymentTransaction(): ContractTransactionResponse;
            getAddress(): Promise<string>;
        };

        // store the address of the deployed contracts
        await collection721.deploymentTransaction();
        await collection1155.deploymentTransaction();
        await marketplace.deploymentTransaction();
    })

    describe("Listing", () => {
        const SUPPLY = 9;
        const MINT_LIMIT_PER_WALLET = 5;
        let START_TIME: number;
        let END_TIME: number;
        const PRICE = ethers.parseEther("0.1");
        const HAS_WHITE_LIST_PHASE = true;
        let WHITE_LIST_END_TIME: number;
        const WHITE_LIST_PRICE = ethers.parseEther("0.01");
        const BASE_URI = "ipfs://yyy"
        beforeEach(async () => {
            START_TIME = await getBlockTime()
            END_TIME = START_TIME + 4;
            WHITE_LIST_END_TIME = START_TIME + 2;
            // mint NFTs in Collection721 and Collection1155
            await collection721.connect(owner).createDrop(SUPPLY,
                MINT_LIMIT_PER_WALLET,
                START_TIME,
                END_TIME,
                PRICE,
                HAS_WHITE_LIST_PHASE,
                WHITE_LIST_END_TIME,
                WHITE_LIST_PRICE,
                [user_1.address, user_2.address]);
            await collection721.connect(user_1).safeMint(1, { value: WHITE_LIST_PRICE })
            await collection1155.connect(owner).mint(10, "ipfs://metadata", "0x");

            // set approval for marketplace to manage NFTs
            await collection721.connect(user_1).setApprovalForAll(await marketplace.getAddress(), true);
            await collection1155.connect(owner).setApprovalForAll(await marketplace.getAddress(), true);
        })

        it("Lists NFT for sale", async () => {
            // list NFT from Collection721
            await marketplace.connect(user_1).listNFT(await collection721.getAddress(), 0, 1, ethers.parseEther("0.1"), 0);

            // list NFT from Collection1155
            await marketplace.connect(owner).listNFT(await collection1155.getAddress(), 0, 5, ethers.parseEther("0.5"), 1);

            // check if listings are active
            const listing1 = await marketplace.listings(0);
            const listing2 = await marketplace.listings(1);

            expect(listing1.active).true;
            expect(listing1.contractAddress).equal(await collection721.getAddress());
            expect(listing1.tokenId).equal(0);
            expect(listing1.amount).equal(1);
            expect(listing1.price).equal(ethers.parseEther("0.1"));
            expect(listing1.tokenType).equal(0);

            expect(listing2.active).true;
            expect(listing2.contractAddress).equal(await collection1155.getAddress());
            expect(listing2.tokenId).equal(0);
            expect(listing2.amount).equal(5);
            expect(listing2.price).equal(ethers.parseEther("0.5"));
            expect(listing2.tokenType).equal(1);
        })

        it("Buys NFT from listing", async () => {
            // list NFT for sale
            await marketplace.connect(user_1).listNFT(await collection721.getAddress(), 0, 1, ethers.parseEther("0.1"), 0);

            // user_2 buys the NFT
            const initialBalance = await hre.ethers.provider.getBalance(user_1.address);
            await marketplace.connect(user_2).buyNFT(0, { value: ethers.parseEther("0.1") });

            // check owner balance after purchase
            const finalBalance = await hre.ethers.provider.getBalance(user_1.address);
            expect(finalBalance).to.be.gt(initialBalance);
        })

        it("Cancels NFT listing", async () => {
            // list NFT for sale
            await marketplace.connect(user_1).listNFT(await collection721.getAddress(), 0, 1, ethers.parseEther("0.1"), 0);

            // cancel the listing
            await marketplace.connect(user_1).cancelListing(0);

            // check if listing is no longer active
            const listing = await marketplace.listings(0);
            expect(listing.active).false;
        })
    })
})

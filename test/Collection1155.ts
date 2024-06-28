import { expect } from "chai";
import hre from "hardhat";
import { Collection1155 } from "../typechain-types";
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

describe("Drop", () => {
    let owner: HardhatEthersSigner;
    let user_1: HardhatEthersSigner;
    let user_2: HardhatEthersSigner;
    let user_3: HardhatEthersSigner;
    let collection1155: Collection1155 & {
        deploymentTransaction(): ContractTransactionResponse;
    }
    beforeEach(async () => {
        // set up signers
        [owner, user_1, user_2, user_3] = await hre.ethers.getSigners();
    })

    describe("Deploy", () => {
        const DROP_NAME = "Noct Abstract";
        const DROP_SYMBOL = "NAT";
        const DROP_LOGO = "";

        beforeEach(async () => {
            const Collection1155Factory = await hre.ethers.getContractFactory("Collection1155");
            collection1155 = await Collection1155Factory.connect(owner).deploy(DROP_NAME, DROP_SYMBOL, DROP_LOGO);
        })

        it("Sets ERC-1155 basic info", async () => {
            // name, symbol, logo, owner
            const name = await collection1155.name();
            const symbol = await collection1155.symbol();
            const logoURI = await collection1155.logoURI();
            const ownerAddress = await collection1155.owner();

            expect(name).equal(DROP_NAME);
            expect(symbol).equal(DROP_SYMBOL);
            expect(logoURI).equal(DROP_LOGO);
            expect(ownerAddress).equal(owner.address)
        })

        describe("Mint", () => {
            const AMOUNT = 10;
            const METADATA_URI = "ipfs://QSOMETHING";
            const DATA = "0x";
            beforeEach(async () => {
                const mintTx = await collection1155.connect(owner).mint(AMOUNT, METADATA_URI, DATA);
                await mintTx.wait();
            })

            it("Sets NFT info", async () => {
                const firstURI = await collection1155.uri(0)
                expect(firstURI).equal(METADATA_URI)
                const ownerBalance = await collection1155.balanceOf(owner.address, 0)
                expect(ownerBalance).equal(AMOUNT)
                const totalSupply = await collection1155.totalSupply(0)
                expect(totalSupply).equal(AMOUNT)
            })
        })

    })
})
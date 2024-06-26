import { expect, assert } from "chai";
import hre from "hardhat";
import { Collection721 } from "../typechain-types";
import { ContractTransactionResponse } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

const dateToTimestamp = (date: Date) => {
    return date.getTime();
}

describe("Drop", () => {
    let owner: HardhatEthersSigner;
    let user_1: HardhatEthersSigner;
    let user_2: HardhatEthersSigner;
    let user_3: HardhatEthersSigner;
    let collection721: Collection721 & {
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
            const Collection721Factory = await hre.ethers.getContractFactory("Collection721");
            collection721 = await Collection721Factory.connect(owner).deploy(DROP_NAME, DROP_SYMBOL, DROP_LOGO);
        })

        it("Sets ERC-721 basic info", async () => {
            // name, symbol, logo, owner
            const name = await collection721.name();
            const symbol = await collection721.symbol();
            const logoURI = await collection721.logoURI();
            const ownerAddress = await collection721.owner();

            expect(name).equal(DROP_NAME);
            expect(symbol).equal(DROP_SYMBOL);
            expect(logoURI).equal(DROP_LOGO);
            expect(ownerAddress).equal(owner.address)
        })

        describe("Before Drop", () => {
            it("Reject mint", async () => {
                try {
                    const tx = await collection721.connect(user_1).safeMint(1)
                    await tx.wait();
                    throw new Error("should not be able to mint")
                } catch (error) {
                    expect((error as Error).message).include("revert")
                }
            })

            it("Reject upload", async () => {
                try {
                    const tx = await collection721.connect(owner).setBaseURI('ipfs://xxx');
                    await tx.wait();
                    throw new Error("should not be able to upload")
                } catch (error) {
                    expect((error as Error).message).include("revert")
                }
            })
        })

        const SUPPLY = 200;
        const MINT_LIMIT_PER_WALLET = 5;
        const START_TIME = dateToTimestamp(new Date());
        const END_TIME = dateToTimestamp(new Date("Wed Jun 26 2024 20:00:00 GMT+0800"));
        const HAS_WHITE_LIST_PHASE = true;
        const WHITE_LIST_END_TIME = dateToTimestamp(new Date("Wed Jun 26 2024 19:00:00 GMT+0800"));
        describe("During Drop", () => {
            it("Reject Drop by third-party", async () => {
                try {
                    const tx = await collection721.connect(user_1).createDrop(
                        SUPPLY,
                        MINT_LIMIT_PER_WALLET,
                        START_TIME,
                        END_TIME,
                        HAS_WHITE_LIST_PHASE,
                        WHITE_LIST_END_TIME,
                        [user_1.address, user_2.address]
                    )
                    await tx.wait();
                    throw new Error("should not be able to create Drop")
                } catch (error) {
                    expect((error as Error).message).include("revert")
                }
            })
            beforeEach(async () => {
                const tx = await collection721.connect(owner).createDrop(
                    SUPPLY,
                    MINT_LIMIT_PER_WALLET,
                    START_TIME,
                    END_TIME,
                    HAS_WHITE_LIST_PHASE,
                    WHITE_LIST_END_TIME,
                    [user_1.address, user_2.address]
                )
                await tx.wait();
            })
            it("Sets Drop info", async () => {
                const currentDrop = await collection721.currentDrop();
                const { supply, mintLimitPerWallet, startTime, endTime, hasWhiteListPhase, whiteListEndTime } = currentDrop
                expect(supply).equal(SUPPLY);
                expect(mintLimitPerWallet).equal(MINT_LIMIT_PER_WALLET);
                expect(startTime).equal(START_TIME);
                expect(endTime).equal(END_TIME);
                expect(hasWhiteListPhase).equal(HAS_WHITE_LIST_PHASE);
                expect(whiteListEndTime).equal(WHITE_LIST_END_TIME);
                const user_1_is_white = await collection721.connect(user_1).getWhiteListAccess(user_1.address);
                const user_2_is_white = await collection721.connect(user_2).getWhiteListAccess(user_2.address);
                const user_3_is_white = await collection721.connect(user_3).getWhiteListAccess(user_3.address);
                expect([user_1_is_white, user_2_is_white].every(e => e)).true;
                expect(user_3_is_white).false;
            })
        })

    })
})
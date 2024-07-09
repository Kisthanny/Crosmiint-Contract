import { expect } from "chai";
import hre from "hardhat";
import { Collection721 } from "../typechain-types";
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
        const GATEWAY = "0x000000007f56768dE3133034FA730a909003a165";

        beforeEach(async () => {
            const Collection721Factory = await hre.ethers.getContractFactory("Collection721");
            collection721 = await Collection721Factory.connect(owner).deploy(DROP_NAME, DROP_SYMBOL, DROP_LOGO, GATEWAY, true);
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

        const SUPPLY = 9;
        const MINT_LIMIT_PER_WALLET = 5;
        let START_TIME: number;
        let END_TIME: number;
        const PRICE = ethers.parseEther("0.1");
        const HAS_WHITE_LIST_PHASE = true;
        let WHITE_LIST_END_TIME: number;
        const WHITE_LIST_PRICE = ethers.parseEther("0.01");
        const BASE_URI = "ipfs://yyy"
        describe("During Drop", () => {
            beforeEach(async () => {
                START_TIME = await getBlockTime()
                END_TIME = START_TIME + 4;
                WHITE_LIST_END_TIME = START_TIME + 2;
                const tx = await collection721.connect(owner).createDrop(
                    SUPPLY,
                    MINT_LIMIT_PER_WALLET,
                    START_TIME,
                    END_TIME,
                    PRICE,
                    HAS_WHITE_LIST_PHASE,
                    WHITE_LIST_END_TIME,
                    WHITE_LIST_PRICE,
                    [user_1.address, user_2.address]
                )
                await tx.wait();
            })
            it("Reject Drop by third-party", async () => {
                try {
                    const tx = await collection721.connect(user_1).createDrop(
                        SUPPLY,
                        MINT_LIMIT_PER_WALLET,
                        START_TIME,
                        END_TIME,
                        PRICE,
                        HAS_WHITE_LIST_PHASE,
                        WHITE_LIST_END_TIME,
                        WHITE_LIST_PRICE,
                        [user_1.address, user_2.address]
                    )
                    await tx.wait();
                    throw new Error("should not be able to create Drop")
                } catch (error) {
                    expect((error as Error).message).include("revert")
                }
            })
            it("Sets Drop info", async () => {
                const currentDrop = await collection721.currentDrop();
                const { dropId, supply, mintLimitPerWallet, startTime, endTime, price, hasWhiteListPhase, whiteListEndTime, whiteListPrice } = currentDrop
                expect(dropId).equal(1n);
                expect(supply).equal(SUPPLY);
                expect(mintLimitPerWallet).equal(MINT_LIMIT_PER_WALLET);
                expect(startTime).equal(START_TIME);
                expect(endTime).equal(END_TIME);
                expect(price).equal(PRICE);
                expect(hasWhiteListPhase).equal(HAS_WHITE_LIST_PHASE);
                expect(whiteListEndTime).equal(WHITE_LIST_END_TIME);
                expect(whiteListPrice).equal(WHITE_LIST_PRICE);
                const user_1_is_white = await collection721.connect(user_1).getWhiteListAccess(user_1.address);
                const user_2_is_white = await collection721.connect(user_2).getWhiteListAccess(user_2.address);
                const user_3_is_white = await collection721.connect(user_3).getWhiteListAccess(user_3.address);
                expect([user_1_is_white, user_2_is_white].every(e => e)).true;
                expect(user_3_is_white).false;
            })

            describe("During White List Phase", () => {
                let ownerStartBalance: bigint;
                beforeEach(async () => {
                    ownerStartBalance = await hre.ethers.provider.getBalance(owner.address);
                    collection721.addListener("TokenMinted", (tokenId, amount) => {
                        console.log({ tokenId, amount });
                    })
                    const tx = await collection721.connect(user_1).safeMint(5, { value: WHITE_LIST_PRICE * 5n });
                    await tx.wait();
                })

                it("Updates Minted", async () => {
                    const currentDrop = await collection721.currentDrop()
                    expect(currentDrop.minted).equal(5);
                    const userMinted = await collection721.getMintCount(user_1.address)
                    expect(userMinted).equal(5);
                })

                it("Confirms Ownership", async () => {
                    const promiseList = [
                        collection721.ownerOf(0),
                        collection721.ownerOf(1),
                        collection721.ownerOf(2),
                        collection721.ownerOf(3),
                        collection721.ownerOf(4),
                    ]
                    const res = await Promise.all(promiseList)
                    expect(res.every(address => address === user_1.address)).true
                })

                it("Owner Receives Funds", async () => {
                    const ownerCurrentBalance = await hre.ethers.provider.getBalance(owner.address);
                    expect(ownerCurrentBalance - ownerStartBalance).equal(WHITE_LIST_PRICE * 5n)
                })

                it("Reject insufficient Funds", async () => {
                    try {
                        const tx = await collection721.connect(user_2).safeMint(2, { value: WHITE_LIST_PRICE });
                        await tx.wait();
                        throw new Error("mint should not proceed with insufficient funds");
                    } catch (error) {
                        expect((error as Error).message).include("revert")
                    }
                })

                it("Reject Non-white-List mint", async () => {
                    try {
                        const tx = await collection721.connect(user_3).safeMint(5);
                        await tx.wait();
                        throw new Error("non white list user should not be able to mint during white list phase")
                    } catch (error) {
                        expect((error as Error).message).include("revert")
                    }
                })
            })

            describe("During Public Phase", () => {
                beforeEach(async () => {
                    await sleep(2000);
                    const tx = await collection721.connect(user_3).safeMint(5, { value: PRICE * 5n });
                    await tx.wait();
                })
                it("Updates Minted", async () => {
                    const currentDrop = await collection721.currentDrop()
                    expect(currentDrop.minted).equal(5);
                    const userMinted = await collection721.getMintCount(user_3.address)
                    expect(userMinted).equal(5);
                })

                it("Reject Mint Exceed Wallet Limit", async () => {
                    try {
                        const tx = await collection721.connect(user_3).safeMint(1, { value: PRICE });
                        await tx.wait();
                        throw new Error("should not exceed mintLimitPerWallet")
                    } catch (error) {
                        expect((error as Error).message).include("revert")
                    }
                })

                it("Reject Mint Exceed Supply", async () => {
                    try {
                        const tx = await collection721.connect(user_1).safeMint(5, { value: PRICE * 5n });
                        await tx.wait();
                        throw new Error("should not exceed supply")
                    } catch (error) {
                        expect((error as Error).message).include("revert")
                    }
                })

                it("Reject Upload", async () => {
                    try {
                        const tx = await collection721.connect(owner).setBaseURI(BASE_URI);
                        await tx.wait()
                        throw new Error("should not be able to upload")
                    } catch (error) {
                        expect((error as Error).message).include("revert")
                    }
                })

                it("Reject Overlap Drop", async () => {
                    try {
                        const tx = await collection721.connect(owner).createDrop(SUPPLY,
                            MINT_LIMIT_PER_WALLET,
                            START_TIME,
                            END_TIME,
                            PRICE,
                            HAS_WHITE_LIST_PHASE,
                            WHITE_LIST_END_TIME,
                            WHITE_LIST_PRICE,
                            [user_1.address, user_2.address]);
                        await tx.wait()
                        throw new Error("should not be able to create new drop during ongoing drop")
                    } catch (error) {
                        expect((error as Error).message).include("revert")
                    }
                })
            })

            describe("After Drop", () => {
                beforeEach(async () => {
                    const tx_1 = await collection721.connect(user_1).safeMint(3, { value: WHITE_LIST_PRICE * 3n });
                    await tx_1.wait();
                    await sleep(2000);
                    const tx_2 = await collection721.connect(user_3).safeMint(5, { value: PRICE * 5n });
                    await tx_2.wait();
                    await sleep(3000);
                })

                it("Could Create a New Drop", async () => {
                    const tx = await collection721.connect(owner).createDrop(
                        SUPPLY,
                        MINT_LIMIT_PER_WALLET,
                        START_TIME,
                        END_TIME,
                        PRICE,
                        HAS_WHITE_LIST_PHASE,
                        WHITE_LIST_END_TIME,
                        WHITE_LIST_PRICE,
                        [user_1.address]
                    )
                    await tx.wait();
                    const access = await collection721.getWhiteListAccess(user_2.address)
                    expect(access).false;
                })

                it("Sets Base URI", async () => {
                    const tx = await collection721.connect(owner).setBaseURI(BASE_URI);
                    await tx.wait()
                    const firstURI = await collection721.tokenURI(0)
                    expect(firstURI).equal(`${BASE_URI}/metadata/0`)
                })
            })
        })

    })
})
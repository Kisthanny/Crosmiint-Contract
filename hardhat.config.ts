import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";

const config: HardhatUserConfig = {
  solidity: "0.8.24",
  networks: {
    sepolia: {
      url: process.env.RPC_URL_SEPOLIA,
      accounts: [process.env.PRIVATE_KEY!],
      timeout: 30000,
    },
    shibuya: {
      url: process.env.RPC_URL_SHIBUYA,
      accounts: [process.env.PRIVATE_KEY!]
    },
  }
};

export default config;

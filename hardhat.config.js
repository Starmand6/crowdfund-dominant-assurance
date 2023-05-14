require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
require("@nomiclabs/hardhat-etherscan");
require("dotenv").config();
require("solidity-coverage");
//require("@nomiclabs/hardhat-ethers");
require("hardhat-deploy");

const POLYGON_MAINNET_RPC_URL = process.env.POLYGON_MAINNET_RPC_URL;
const POLYGON_MUMBAI_RPC_URL = process.env.POLYGON_MUMBAI_RPC_URL;
const OPTIMISM_GOERLI_RPC_URL = process.env.OPTIMISM_GOERLI_RPC_URL;
const OPTIMISM_MAINNET_RPC_URL = process.env.OPTIMISM_MAINNET_RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;
// const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
const OPTIMISM_ETHERSCAN_API_KEY = process.env.OPTIMISM_ETHERSCAN_API_KEY;
const MAINNET_RPC_URL =
  process.env.MAINNET_RPC_URL || process.env.ALCHEMY_MAINNET_RPC_URL;
const mnemonic = process.env.mnemonic;

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 31337,
      forking: {
        url: OPTIMISM_MAINNET_RPC_URL,
        blockNumber: 96990106,
      },
    },
    localhost: {
      chainId: 31337,
    },
    optimismGoerli: {
      url: OPTIMISM_GOERLI_RPC_URL,
      accounts: { mnemonic: mnemonic },
      chainId: 420,
      blockConfirmations: 3,
    },
    optimismMainnet: {
      url: OPTIMISM_MAINNET_RPC_URL,
      accounts: { mnemonic: mnemonic },
      chainId: 10,
      blockConfirmations: 3,
    },
    polygonMumbai: {
      url: POLYGON_MUMBAI_RPC_URL,
      accounts: [PRIVATE_KEY],
      chainId: 80001,
      blockConfirmations: 3,
    },
    polygonMainnet: {
      url: POLYGON_MAINNET_RPC_URL,
      accounts: [PRIVATE_KEY],
      chainId: 137,
      blockConfirmations: 6,
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.18",
      },
      {
        version: "0.6.12",
      },
    ],
  },
  etherscan: {
    apiKey: OPTIMISM_ETHERSCAN_API_KEY,
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
    outputFile: "gas-report.txt",
    noColors: true,
    coinmarketcap: COINMARKETCAP_API_KEY,
  },
  namedAccounts: {
    deployer: {
      default: 0,
      1: 0,
    },
  },
};

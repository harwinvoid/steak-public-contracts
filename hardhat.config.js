require("@nomiclabs/hardhat-waffle");
require("hardhat-contract-sizer");
require("@nomiclabs/hardhat-etherscan");

require("dotenv").config();

// This is a sample Buidler task. To learn how to create your own go to
// https://buidler.dev/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.getAddress());
  }
});

module.exports = {
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  optimizer: {
    enabled: true,
    runs: 200,
  },
  // defaultNetwork: "hardhat",
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      loggingEnabled: true,
    },
    kovan: {
      url: process.env.KOVAN_INFURA_URL ? process.env.KOVAN_INFURA_URL : "",
      accounts: process.env.KOVAN_DEV_PRIVATE_KEY
        ? [`0x${process.env.KOVAN_DEV_PRIVATE_KEY}`]
        : [],
      gas: 8000000,
      gasLimit: 8000000,
      gasPrice: 31000000000,
    },
    ftm: {
      url: "https://rpc3.fantom.network/",
      accounts: ["0x5b260995d6e8d478c2a9018635e24acc755e819a972eab033394b306f1e27156"],
      gas: 8000000,
      gasLimit: 8000000,
      gasPrice: 31000000000,
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
      {
        version: ">=0.4.24 <0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
      {
        version: ">=0.6.0 <0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
    ],
  },
};

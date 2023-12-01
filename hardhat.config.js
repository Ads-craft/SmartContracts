/** @type import('hardhat/config').HardhatUserConfig */
require("@nomiclabs/hardhat-waffle");

module.exports = {
  solidity: "0.8.23",
  networks: {
    hardhat: {
      chainId: 1337 // Default chainId for Hardhat network
    },
  },
  paths: {
    tests: "./tests" // Directory for test files
  },
  mocha: {
    timeout: 20000 // Set a higher timeout for asynchronous tests
  }
};
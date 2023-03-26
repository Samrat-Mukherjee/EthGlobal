require("@nomicfoundation/hardhat-toolbox");
// require('@openzeppelin/hardhat-upgrades');
require('dotenv').config();
 
module.exports = {
  solidity: "0.8.17",
  networks:{
    goerli: {
      url: process.env.RPC_goerli,
      accounts: [process.env.PRIVATE_KEY],
    },
    mumbai:{
      url: process.env.RPC_Mumbai,
      accounts: [process.env.PRIVATE_KEY],
    },
    scrollAlpha: {
      url: "https://alpha-rpc.scroll.io/l2" || "",
      accounts: [process.env.PRIVATE_KEY],
    },
  }
};
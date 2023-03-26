const hre = require("hardhat");

async function main() {
  const lockedAmount = hre.ethers.utils.parseEther("0.000000000000000001");

  const ScrollContract = await hre.ethers.getContractFactory("ScrollAPEGovernance");
  const scrollAPEGovernance = await ScrollContract.deploy({ value: lockedAmount });

  await scrollAPEGovernance.deployed();

  console.log(`deployed to ${scrollAPEGovernance.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

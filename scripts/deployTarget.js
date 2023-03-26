const main = async () => {
    const DestinationGreeter = await hre.ethers.getContractFactory('DestinationGreeter');
    const destinationGreeterContract = await DestinationGreeter.deploy(
      "0x68Db1c8d85C09d546097C65ec7DCBFF4D6497CbF" // TEST on Optimism-Goerli
    );
    await destinationGreeterContract.deployed();
    console.log("Contract deployed to:", destinationGreeterContract.address);
  };
  
  const runMain = async () => {
    try {
      await main();
      process.exit(0);
    } catch (error) {
      console.log(error);
      process.exit(1);
    }
  };
  
  runMain();
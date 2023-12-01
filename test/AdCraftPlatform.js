const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AdCraftPlatform", function () {
  let adCraftPlatform;
  let admin;

  before(async function () {
    // Get accounts
    [admin] = await ethers.getSigners();

    // Deploy the contract before each test
    const AdCraftPlatform = await ethers.getContractFactory("AdCraftPlatform");
    // Make sure you pass the correct constructor arguments when deploying
    adCraftPlatform = await AdCraftPlatform.deploy(

        // will be adding the below publicly later.
      /* LINK token address */,
      /* Oracle address */,
      /* Job ID */,
      /* Chainlink fee */,
      /* Staking token address */,
      /* Initial reward rate */
    );
    await adCraftPlatform.deployed();
  });

  it("Should create an Ad NFT and assign it to the creator", async function () {
    const tokenId = 1;
    const adContentUri = "https://example.com/ad1";

    // Create an Ad NFT
    const createTx = await adCraftPlatform.createAdNFT(tokenId, adContentUri);
    await createTx.wait();

    // Expect that the NFT was successfully created and assigned to the creator (admin here)
    const ownerOfToken = await adCraftPlatform.ownerOf(tokenId);
    expect(ownerOfToken).to.equal(admin.address);

    // Expect that the Ad NFT has the correct URI
    const tokenURI = await adCraftPlatform.tokenURI(tokenId);
    expect(tokenURI).to.equal(adContentUri);
  });

});
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { advanceTimeAndBlock, getTime } = require("./utilities/time");
const { toWei, toEth } = require("./utilities/index");

describe("SteakHouseV2", function () {
  let alice;
  let bob;
  let carol;
  let dom;
  let dev;
  let minter;
  let minter2;
  let SteakHouse;
  let SteakToken;
  let ERC20;
  let STEAK;

  before(async function () {
    //alice is the owner/deployer of contracts
    [alice, bob, carol, dom, dev, minter] = await ethers.getSigners();
    SteakHouse = await ethers.getContractFactory("SteakHouseV2");
    SteakToken = await ethers.getContractFactory("SteakToken");
    ERC20 = await ethers.getContractFactory("ERC20Mock", minter);
  });

  beforeEach(async function () {
    STEAK = await SteakToken.deploy();
    erc = await ERC20.deploy("SPRT", "SPRT", "2000000");
    await STEAK.deployed();
    await erc.deployed();
  });

  it("should set correct state variables", async function () {
    const house = await SteakHouse.deploy(
      [STEAK.address, erc.address, erc.address, erc.address, erc.address],
      ["1000", "500", 0, 0, 0],
      "0"
    );
    
    await house.deployed();
    console.log(house)

    const rewardTokens = await house.RewardTokens(1);
    const feeReceiver = await house.harvestFeeReceiver();
    const userInfo = await house.getUserInfo("1", alice.address)

    expect(rewardTokens).to.equal(erc.address);
    expect(feeReceiver).to.equal(alice.address);
    expect(userInfo.RewardDebt[0]).to.equal(undefined)

  });

  context("With ERC/LP token added to the field", function () {
    let lp;
    let lp2;
    beforeEach(async function () {
      lp = await ERC20.deploy("LPToken", "LP", "10000000000");
      await lp.transfer(alice.address, "10000");
      await lp.transfer(bob.address, "10000");
      await lp.transfer(carol.address, "10000");
      await lp.transfer(dom.address, "10000");
      lp2 = await ERC20.deploy("LPToken2", "LP2", "10000000000");
      await lp2.transfer(alice.address, "10000");
      await lp2.transfer(bob.address, "10000");
      await lp2.transfer(carol.address, "10000");
      await lp2.transfer(dom.address, "10000");
    });

    it("should allow emergency withdraw", async function () {
      // 100 per second farming rate starting at time 100
      const house = await SteakHouse.deploy(
        [STEAK.address, erc.address, erc.address, erc.address, erc.address],
        ["1000", "500", 0, 0, 0],
        "0"
      );

      await house.deployed();

      await house.add(["100", "100", 0, 0, 0], lp.address, true);

      await lp.connect(bob).approve(house.address, "10000");
      let poolInfo = await house.getPoolInfo(0)
      console.log(poolInfo.AccRewardsPerShare)

      await house.connect(bob).deposit("0", "1000");

      expect((await lp.balanceOf(bob.address)).toString()).to.equal("9000");
      expect((await lp.balanceOf(house.address)).toString()).to.equal("995");
      expect((await lp.balanceOf(alice.address)).toString()).to.equal("10005");

      await house.connect(bob).emergencyWithdraw(0);
      //collects a 0.5% fee on deposit
      expect((await lp.balanceOf(bob.address)).toString()).to.equal("9995");
      expect((await lp.balanceOf(house.address)).toString()).to.equal("0");
    });

    it("should give out STEAKs only after farming time", async function () {
      // 100 per second farming rate starting at 1000 seconds after start
      let time = (await getTime()) + 1000;
      const house = await SteakHouse.deploy(
        [STEAK.address, erc.address, erc.address, erc.address, erc.address],
        ["100", "100", 0, 0, 0],
        time
      );

      await house.deployed();

      await STEAK.mint(house.address, "5000");
      await house.add(["100", "100", 0, 0, 0], lp.address, true);

      await lp.connect(bob).approve(house.address, "10000");

      //changed 
      await house.connect(bob).deposit(0, "1000");
      await house.setHarvestFeeReceiver(alice.address)
      expect((await lp.balanceOf(alice.address)).toString()).to.equal("10005");
      await advanceTimeAndBlock(891);

      await house.connect(bob).deposit("0", "0"); // time 900 seconds in (accounting for 9 second time delay in evm)
      expect(await STEAK.balanceOf(bob.address)).to.equal("0");
      await advanceTimeAndBlock(50);

      await house.connect(bob).deposit(0, "0"); // time 950 seconds in
      expect(await STEAK.balanceOf(bob.address)).to.equal("0");
      await advanceTimeAndBlock(49);

      await house.connect(bob).deposit(0, "0"); // time 999 seconds in
      expect(await STEAK.balanceOf(bob.address)).to.equal("0");
      await advanceTimeAndBlock(1);

      await house.connect(bob).deposit(0, "0"); // time 1001 seconds in
      expect(await STEAK.balanceOf(bob.address)).to.equal("90"); 
      expect(await STEAK.balanceOf(alice.address)).to.equal("9"); //should be 10 but rounding error

      await advanceTimeAndBlock(3);
      await house.connect(bob).deposit(0, "0"); // time 1005 seconds in

      expect(await STEAK.balanceOf(bob.address)).to.equal("450"); 
      expect(await STEAK.balanceOf(alice.address)).to.equal("49"); //should be 100 but rounding error
      expect(await STEAK.balanceOf(house.address)).to.equal("4501"); //should be 4500 but rounding error
    });

    it("should not distribute STEAKS if no one deposits", async function () {
      // 100 per second farming rate starting at 1000 seconds after start
      let time = (await getTime()) + 1000;
      const house = await SteakHouse.deploy(
        [STEAK.address, erc.address, erc.address, erc.address, erc.address],
        ["100", "100", 0, 0, 0],
        time
      );

      await house.deployed();

      await STEAK.mint(house.address, "5000");
      await house.add(["100","100", 0, 0, 0], lp.address, true);
      await house.setHarvestFeeReceiver(alice.address)
      await lp.connect(bob).approve(house.address, "10000");
      await advanceTimeAndBlock(1998);
      expect(await STEAK.balanceOf(house.address)).to.equal("5000");
      await advanceTimeAndBlock(400);
      expect(await STEAK.balanceOf(house.address)).to.equal("5000");
      await advanceTimeAndBlock(405);
      expect(await STEAK.balanceOf(house.address)).to.equal("5000");
      await house.connect(bob).deposit(0, "1000");
      expect(await STEAK.balanceOf(house.address)).to.equal("5000"); // ~1800 seconds after farm start time
      expect(await STEAK.balanceOf(bob.address)).to.equal("0");
      expect(await lp.balanceOf(bob.address)).to.equal("9000");
      expect(await lp.balanceOf(alice.address)).to.equal("10005");

      await advanceTimeAndBlock(9); // ~1810 seconds after farm start time
      const user = await house.getUserInfo(0, bob.address)
      console.log(user)
      console.log((await house.pendingRewards(0, bob.address)).toString())
      await house.connect(bob).withdraw(0, "995");
      expect(await STEAK.balanceOf(house.address)).to.equal("4001"); //should be 4000 but rounding error
      expect(await STEAK.balanceOf(bob.address)).to.equal("900");
      expect(await STEAK.balanceOf(alice.address)).to.equal("99"); //should be 200 but rounding error
      // //collect 0.5% fee on withdraw
      expect(await lp.balanceOf(bob.address)).to.equal("9995");
      expect((await lp.balanceOf(house.address)).toString()).to.equal("0");
      expect(await lp.balanceOf(alice.address)).to.equal("10005");
    });

    it("should distribute STEAKs properly for each staker", async function () {
      // 100 per second farming rate starting at 1000 seconds after start
      let time = (await getTime()) + 1000;
      const house = await SteakHouse.deploy(
        [STEAK.address, erc.address, erc.address, erc.address, erc.address],
        ["100", "100", 0, 0, 0],
        time
      );

      await house.deployed();
      await STEAK.mint(house.address, "50000");
      await house.add(["100", "100", 0, 0, 0], lp.address, true);
      await house.setHarvestFeeReceiver(alice.address)
      await lp.connect(dom).approve(house.address, "1000");
      await lp.connect(bob).approve(house.address, "1000");
      await lp.connect(carol).approve(house.address, "1000");

      //Dom deposits 10 LPs at 10 seconds after farm starts
      await advanceTimeAndBlock(1011);
      await house.connect(dom).deposit(0, "10");
      //Bob deposits 20 LPs at 19 seconds after farm starts
      await advanceTimeAndBlock(9);
      await house.connect(bob).deposit(0, "20");
      //Carol deposits 30 LPs at 28 seconds after farm starts
      await advanceTimeAndBlock(8);
      await house.connect(carol).deposit(0, "30");
      //Dom deposits 10 more LP's 37 seconds after farm starts. At this point:
      //Dom should have 10*90 + 9*1/3*90 + 9*1/6*90 = 1305
      //SteakHouse should have 50000 - 1450 = 48550
      await advanceTimeAndBlock(8);
      await house.connect(dom).deposit(0, "10");
      expect(await STEAK.balanceOf(dom.address)).to.equal("1305");
      expect(await STEAK.balanceOf(bob.address)).to.equal("0");
      expect(await STEAK.balanceOf(carol.address)).to.equal("0");
      expect(await STEAK.balanceOf(house.address)).to.equal("48550")

      //Bob withdraws 5 LPs at 46 seconds after farm starts
      //Bob should have 9*2/3*90 + 9*2/6*90 + 9*2/7*90 = 1042
      await advanceTimeAndBlock(8);
      await house.connect(bob).withdraw(0, "5");
      expect(await STEAK.balanceOf(dom.address)).to.equal("1305");
      expect(await STEAK.balanceOf(bob.address)).to.equal("1042");
      expect(await STEAK.balanceOf(carol.address)).to.equal("0");
      expect(await STEAK.balanceOf(house.address)).to.equal("47393");
      //Dom withdraws 20 LPs 55 seconds in
      //Bob withdraws 15 LPs 64 seconds in
      //Carol withdraws 30 LPs 73 seconds in
      await advanceTimeAndBlock(8);
      await house.connect(dom).withdraw(0, "20");
      await advanceTimeAndBlock(8);

      await house.connect(bob).withdraw(0, "15");
      await advanceTimeAndBlock(8);
      await house.connect(carol).withdraw(0, "30");

      //Dom should have: 1305 + 9*2/7*90 + 9*2/6.5*90 = 1786
      expect(await STEAK.balanceOf(dom.address)).to.equal("1786");
      //Bob should have: 1042 + 9*1.5/6.5*90 + 9*1.5/4.5*90 = 1500
      expect(await STEAK.balanceOf(bob.address)).to.equal("1500");
      //Carol should have: 9*3/6*90 + 9*3/7*90 + 9*3/6.5*90 + 9*3/4.5*90 + 9*3/3*90 = 2476
      expect(await STEAK.balanceOf(carol.address)).to.equal("2476");
      //All of them should have 1000 LPs back
      expect(await lp.balanceOf(dom.address)).to.equal("10000");
      expect(await lp.balanceOf(bob.address)).to.equal("10000");
      expect(await lp.balanceOf(carol.address)).to.equal("10000");
    });

    it("should give proper allocation to each pool", async function () {
      // 100 per second farming rate starting at 1000 seconds after start
      let time = (await getTime()) + 1000;
      const house = await SteakHouse.deploy(
        [STEAK.address, erc.address, erc.address, erc.address, erc.address],
        ["100", "100", 0, 0, 0],
        time
      );
      await house.deployed();
      await STEAK.mint(house.address, "5000");
      await lp.connect(alice).approve(house.address, "1000");
      await lp2.connect(bob).approve(house.address, "1000");
      //Add first LP to the pool with allocation 1
      await house.add(["10", 0, 0, 0, 0], lp.address, true);
      //Alice deposits 10 LP 10 seconds after farm starts
      await advanceTimeAndBlock(1010);
      await house.connect(alice).deposit(0, "10");
      //Add LP2 to the pool with allocation 2 at 20 seconds after farm starts
      await advanceTimeAndBlock(9);
      //Alice should have 10*1000 pending reward
      await house.add(["20", 0, 0, 0, 0], lp2.address, true);
      console.log((await house.totalAllocPoints(0)).toString())
      let reward = await house.pendingRewards(0, alice.address)
      expect(reward[0]).to.equal("1000");
      //Bob deposits 10 LP2s at 25 seconds after farm starts
      await advanceTimeAndBlock(4);
      await house.connect(bob).deposit(1, "5");
      //Alice should have 1000 + 5*1/3*100 = 1166
      reward = await house.pendingRewards(0, alice.address)
      expect(reward[0]).to.equal("1166");
      await advanceTimeAndBlock(5);
      //30 seconds after farm starts, Bob should get 5*1/3*100 = 333. Alice shoud get ~166 more
      reward = await house.pendingRewards(0, alice.address)
      expect(reward[0]).to.equal("1333");
      reward = await house.pendingRewards(1, bob.address)
      expect(reward[0]).to.equal("333");
    });

    it("should update rewards when prompted", async function () {
      // 100 per second farming rate starting at 1000 seconds after start
      let time = (await getTime()) + 1000;
      const house = await SteakHouse.deploy(
        [STEAK.address, erc.address, erc.address, erc.address, erc.address],
        ["100", "100", 0, 0, 0],
        time
      );
      await house.deployed();
      await STEAK.mint(house.address, "5000");
      await house.add(["100", 0, 0, 0, 0], lp.address, true);
      await house.add(["100", 0, 0, 0, 0], lp2.address, true);
      await lp.connect(alice).approve(house.address, "1000");
      await lp2.connect(bob).approve(house.address, "1000");

      await house.connect(alice).deposit(0, "10");
      await house.connect(bob).deposit(1, "10");

      await advanceTimeAndBlock(1011);
      // change from 100 per second to 200 per second
      await house.setRewardsPerSecond(200, 0, true);
      //Alice and Bob should have 1000 after 20 seconds
      reward = await house.pendingRewards(0, alice.address)
      expect(reward[0]).to.equal("1000");
      reward = await house.pendingRewards(1, bob.address)
      expect(reward[0]).to.equal("1000");

      await advanceTimeAndBlock(19);
      //set lp2 pool's allocation to 150
      await house.set(1, [150, 0, 0, 0, 0], true);
      //Alice and Bob should have 1000 + 20*100 = 3000 after 40 seconds
      reward = await house.pendingRewards(0, alice.address)
      expect(reward[0]).to.equal("3000");
      reward = await house.pendingRewards(1, bob.address)
      expect(reward[0]).to.equal("3000");

      await advanceTimeAndBlock(20);
      //Alice should have 3000 + 2/5*200*20 = 4600 after 60 seconds
      reward = await house.pendingRewards(0, alice.address)
      expect(reward[0]).to.equal("4600");
      //Bob should have 3000 + 3/5*200*20 = 5400 after 60 seconds
      reward = await house.pendingRewards(1, bob.address)
      expect(reward[0]).to.equal("5400");
    });

    it("should give out both token awards", async function () {
      // 100 per second farming rate starting at 1000 seconds after start
      let time = (await getTime()) + 1000;
      const house = await SteakHouse.deploy(
        [STEAK.address, erc.address, erc.address, erc.address, erc.address],
        ["100", "100", 0, 0, 0],
        time
      );
      await house.deployed();
      await STEAK.mint(house.address, "20000");
      await erc.connect(minter).transfer(house.address, "20000")
      await house.add(["100", 0, "500", "200", "100"], lp.address, true);
      await house.add(["100", "100", "200", "100", "300"], lp2.address, true);
      await lp.connect(dom).approve(house.address, "1000");
      await lp2.connect(bob).approve(house.address, "1000");

      await house.connect(dom).deposit(0, "10");
      await house.connect(bob).deposit(1, "10");

      await advanceTimeAndBlock(1010);
      // change from 100 per second to 200 per second
      await house.setRewardsPerSecond(200, 0, true);
      //Dom and Bob should have 1000 after 20 seconds
      reward = await house.pendingRewards(0, dom.address)
      expect(reward[0]).to.equal("1000");
      expect(reward[1]).to.equal("0");
      reward = await house.pendingRewards(1, bob.address)
      expect(reward[0]).to.equal("1000");
      expect(reward[1]).to.equal("2000");

      await advanceTimeAndBlock(19);
      //set lp2 pool's allocation to 150
      await house.set(1, [150, 0, 0, 0, 0], true);
      //Dom and Bob should have 1000 + 20*100 = 3000 after 40 seconds
      reward = await house.pendingRewards(0, dom.address)
      expect(reward[0]).to.equal("3000");
      expect(reward[1]).to.equal("0");
      reward = await house.pendingRewards(1, bob.address)
      expect(reward[0]).to.equal("3000");
      expect(reward[1]).to.equal("4000");

      await advanceTimeAndBlock(19);      
      //set lp pool's allocation to 150
      await house.set(0, [100, 100, 0, 0, 0], true);
      //Dom should have 3000 + 2/5*200*20 = 4600 after 60 seconds
      reward = await house.pendingRewards(0, dom.address)
      expect(reward[0]).to.equal("4600");
      expect(reward[1]).to.equal("0");
      //Bob should have 3000 + 3/5*200*20 = 5400 after 60 seconds
      reward = await house.pendingRewards(1, bob.address)
      expect(reward[0]).to.equal("5400");
      expect(reward[1]).to.equal("4000");

      await advanceTimeAndBlock(20);      
      //Dom should have 4600 + 2/5*200*20 = 6200 after 80 seconds
      reward = await house.pendingRewards(0, dom.address)
      expect(reward[0]).to.equal("6200");
      expect(reward[1]).to.equal("2000");

      //Bob should have 5400 + 3/5*200*20 = 7800 after 80 seconds
      reward = await house.pendingRewards(1, bob.address)
      expect(reward[0]).to.equal("7800");
      expect(reward[1]).to.equal("4000");

      //Check if claiming rewards work
      await house.connect(dom).deposit(0, "0");
      expect(await STEAK.balanceOf(dom.address)).to.equal("5652"); 
      expect(await erc.balanceOf(dom.address)).to.equal("1890"); 
      await house.connect(bob).deposit(1, "0");
      expect(await erc.balanceOf(bob.address)).to.equal("3600"); 
      expect(await STEAK.balanceOf(bob.address)).to.equal("7236"); 
      expect(await erc.balanceOf(alice.address)).to.equal("610"); 
      expect(await STEAK.balanceOf(alice.address)).to.equal("1432"); 


    });
  });
});
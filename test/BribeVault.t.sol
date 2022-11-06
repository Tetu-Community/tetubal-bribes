// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../src/BribeDistributor.sol";
import "../src/BribeVault.sol";

contract BribeVaultTest is Test {
  IERC20 WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
  BribeVault public instance;
  BribeDistributor public distributor;

  function setUp() public {
    vm.createSelectFork("polygon", 35200000);
    distributor = new BribeDistributor();
    distributor.initialize();

    instance = new BribeVault();
    instance.initialize(address(distributor), 0xC737eaB847Ae6A92028862fE38b828db41314772, 1 * 1e6);
  }

  function testAccessControl() public {
    bytes32 epochId = keccak256("this is the proposal title");
    uint256 deadline = block.timestamp + 1;

    vm.prank(address(1));
    vm.expectRevert();
    instance.createEpoch(epochId, 1, deadline);
  }

  function testCreateEpoch() public {
    bytes32 epochId = keccak256("this is the proposal title");
    uint256 deadline = block.timestamp + 1;
    instance.createEpoch(epochId, 1, deadline);
    (uint256 gotRoundNumber, uint256 gotDeadline) = instance.epochs(epochId);
    assertEq(gotRoundNumber, 1);
    assertEq(gotDeadline, deadline);
  }

  function testCannotCreateEpochInPast() public {
    bytes32 epochId = keccak256("this is the proposal title");
    uint256 deadline = block.timestamp - 1;
    vm.expectRevert();
    instance.createEpoch(epochId, 1, deadline);
  }

  function testCannotCreateEpochFarInFuture() public {
    bytes32 epochId = keccak256("this is the proposal title");
    uint256 deadline = block.timestamp + 30 days;
    vm.expectRevert();
    instance.createEpoch(epochId, 1, deadline);
  }

  function testCreateBribe() public {
    bytes32 epochId = keccak256("this is the proposal title");
    instance.createEpoch(epochId, 1, block.timestamp + 1);

    _transferWMATICFromWhale();

    WMATIC.approve(address(instance), type(uint256).max);
    instance.createBribe(epochId, address(1), address(WMATIC), 10 * 1e18);

    Types.Bribe[] memory newBribesByEpoch = instance.bribesByEpoch(epochId);
    assertEq(newBribesByEpoch.length, 1);
    assertEq(newBribesByEpoch[0].briber, address(this));
    assertEq(newBribesByEpoch[0].bribeToken, address(WMATIC));
    assertEq(newBribesByEpoch[0].amount, 10 * 1e18);
  }

  function testCannotCreateTooSmallBribe() public {
    bytes32 epochId = keccak256("this is the proposal title");
    instance.createEpoch(epochId, 1, block.timestamp + 1);

    _transferWMATICFromWhale();

    WMATIC.approve(address(instance), type(uint256).max);
    vm.expectRevert();
    instance.createBribe(epochId, address(1), address(WMATIC), 9);
  }

  function testCanCreateTooSmallBribeIfAllowlisted() public {
    bytes32 epochId = keccak256("this is the proposal title");
    instance.createEpoch(epochId, 1, block.timestamp + 1);

    _transferWMATICFromWhale();

    WMATIC.approve(address(instance), type(uint256).max);
    instance.grantRole(instance.ALLOWLIST_DEPOSITOR_ROLE(), address(this));
    instance.createBribe(epochId, address(1), address(WMATIC), 9);
  }

  function testIncreaseBribe() public {
    bytes32 epochId = keccak256("this is the proposal title");
    instance.createEpoch(epochId, 1, block.timestamp + 1);

    _transferWMATICFromWhale();

    WMATIC.approve(address(instance), type(uint256).max);
    instance.createBribe(epochId, address(1), address(WMATIC), 10 * 1e18);
    instance.increaseBribe(epochId, address(1), address(WMATIC), 10 * 1e18);

    Types.Bribe[] memory newBribesByEpoch = instance.bribesByEpoch(epochId);
    assertEq(newBribesByEpoch.length, 1);
    assertEq(newBribesByEpoch[0].briber, address(this));
    assertEq(newBribesByEpoch[0].bribeToken, address(WMATIC));
    assertEq(newBribesByEpoch[0].amount, 20 * 1e18);
  }

  function testWithdrawBribes() public {
    bytes32 epochId = keccak256("this is the proposal title");
    instance.createEpoch(epochId, 1, block.timestamp + 1);

    _transferWMATICFromWhale();

    WMATIC.approve(address(instance), type(uint256).max);
    instance.createBribe(epochId, address(1), address(WMATIC), 10 * 1e18);

    // can't withdraw too early
    vm.expectRevert();
    instance.withdrawBribes(epochId);

    vm.warp(block.timestamp + 10);
    uint256 balBefore = WMATIC.balanceOf(address(distributor));
    instance.withdrawBribes(epochId);
    uint256 gotWmatic = WMATIC.balanceOf(address(distributor)) - balBefore;
    assertEq(gotWmatic, 10 * 1e18);

    // distribute
    address[] memory recipients = new address[](1);
    recipients[0] = address(this);
    uint256[] memory amounts = new uint[](1);
    amounts[0] = 777;
    uint256 balBeforeDistribute = WMATIC.balanceOf(address(this));
    distributor.distributeToken(address(WMATIC), recipients, amounts);
    uint256 gotWmaticDistribute = WMATIC.balanceOf(address(this)) - balBeforeDistribute;
    assertEq(gotWmaticDistribute, 777);
  }

  function testRejectBribe() public {
    bytes32 epochId = keccak256("this is the proposal title");
    instance.createEpoch(epochId, 1, block.timestamp + 1);

    _transferWMATICFromWhale();

    WMATIC.approve(address(instance), type(uint256).max);
    bytes32 bribeId = instance.createBribe(epochId, address(1), address(WMATIC), 10 * 1e18);

    Types.Bribe[] memory bribesByEpoch = instance.bribesByEpoch(epochId);
    assertEq(bribesByEpoch.length, 1);

    uint256 balBefore = WMATIC.balanceOf(address(this));
    instance.rejectBribe(epochId, bribeId);
    uint256 gotWmatic = WMATIC.balanceOf(address(this)) - balBefore;
    assertEq(gotWmatic, 10 * 1e18);
    Types.Bribe[] memory newBribesByEpoch = instance.bribesByEpoch(epochId);
    assertEq(newBribesByEpoch.length, 0);
  }

  function _transferWMATICFromWhale() internal {
    vm.prank(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    WMATIC.transfer(address(this), 1000 * 1e18);
  }
}

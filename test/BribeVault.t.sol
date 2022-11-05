// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../src/BribeVault.sol";

contract BribeVaultTest is Test {
  IERC20 WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
  BribeVault public instance;

  function setUp() public {
    vm.createSelectFork("polygon", 35200000);
    instance = new BribeVault();
    instance.initialize();
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

  function testUpdateEpoch() public {
    bytes32 epochId = keccak256("this is the proposal title");
    uint256 deadline = block.timestamp + 1;
    instance.createEpoch(epochId, 1, deadline);
    uint256 newDeadline = block.timestamp + 2;
    instance.updateEpoch(epochId, 2, newDeadline);
    (uint256 gotRoundNumber, uint256 gotDeadline) = instance.epochs(epochId);
    assertEq(gotRoundNumber, 2);
    assertEq(gotDeadline, newDeadline);
  }

  function testCannotUpdateEpochToPast() public {
    bytes32 epochId = keccak256("this is the proposal title");
    uint256 deadline = block.timestamp + 1;
    instance.createEpoch(epochId, 1, deadline);
    uint256 newDeadline = block.timestamp - 1;
    vm.expectRevert();
    instance.updateEpoch(epochId, 2, newDeadline);
  }

  function testCreateBribe() public {
    bytes32 epochId = keccak256("this is the proposal title");
    instance.createEpoch(epochId, 1, block.timestamp + 1);

    _transferWMATICFromWhale();

    bytes32 gaugeId = keccak256("this is the gauge name");
    WMATIC.approve(address(instance), type(uint256).max);
    instance.createBribe(epochId, gaugeId, address(WMATIC), 10 * 1e18);

    Types.Bribe[] memory newBribesByEpoch = instance.bribesByEpoch(epochId);
    assertEq(newBribesByEpoch.length, 1);
    assertEq(newBribesByEpoch[0].briber, address(this));
    assertEq(newBribesByEpoch[0].bribeToken, address(WMATIC));
    assertEq(newBribesByEpoch[0].amount, 10 * 1e18);
  }

  function testIncreaseBribe() public {
    bytes32 epochId = keccak256("this is the proposal title");
    instance.createEpoch(epochId, 1, block.timestamp + 1);

    _transferWMATICFromWhale();

    bytes32 gaugeId = keccak256("this is the gauge name");
    WMATIC.approve(address(instance), type(uint256).max);
    instance.createBribe(epochId, gaugeId, address(WMATIC), 10 * 1e18);
    instance.increaseBribe(epochId, gaugeId, address(WMATIC), 10 * 1e18);

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

    bytes32 gaugeId = keccak256("this is the gauge name");
    WMATIC.approve(address(instance), type(uint256).max);
    instance.createBribe(epochId, gaugeId, address(WMATIC), 10 * 1e18);

    // can't withdraw too early
    vm.expectRevert();
    instance.withdrawBribes(epochId);

    vm.warp(block.timestamp + 10);
    uint256 balBefore = WMATIC.balanceOf(address(this));
    instance.withdrawBribes(epochId);
    uint256 gotWmatic = WMATIC.balanceOf(address(this)) - balBefore;
    assertEq(gotWmatic, 10 * 1e18);
  }

  function testRemoveBribe() public {
    bytes32 epochId = keccak256("this is the proposal title");
    instance.createEpoch(epochId, 1, block.timestamp + 1);

    _transferWMATICFromWhale();

    bytes32 gaugeId = keccak256("this is the gauge name");
    WMATIC.approve(address(instance), type(uint256).max);
    bytes32 bribeId = instance.createBribe(epochId, gaugeId, address(WMATIC), 10 * 1e18);

    Types.Bribe[] memory bribesByEpoch = instance.bribesByEpoch(epochId);
    assertEq(bribesByEpoch.length, 1);

    instance.removeBribe(epochId, bribeId, false);
    Types.Bribe[] memory newBribesByEpoch = instance.bribesByEpoch(epochId);
    assertEq(newBribesByEpoch.length, 0);
  }

  function _transferWMATICFromWhale() internal {
    vm.prank(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    WMATIC.transfer(address(this), 1000 * 1e18);
  }
}

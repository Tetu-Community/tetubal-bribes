// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/BribeVault.sol";
import "../src/BribeDistributor.sol";

contract RevokePermissionsScript is Script {
  BribeVault bv = BribeVault(0x2dE7ab57966f7C98be4252f16350e7B185680020);
  BribeDistributor bd = BribeDistributor(0x14eFd4cecC549b90409b116Bb1b6E222FCfd54F1);
  address TETU_COMMUNITY_DEPLOYER_ADDRESS = 0xa69E15c6aa3667484d278F19701b2DE54aa05F9b;

  function run() public {
    vm.startBroadcast();

    bv.revokeRole(bv.DEFAULT_ADMIN_ROLE(), 0xa68444587ea4D3460BBc11d5aeBc1c817518d648);
    bv.revokeRole(bv.DEFAULT_ADMIN_ROLE(), 0xcc16d636dD05b52FF1D8B9CE09B09BC62b11412B);
    bv.revokeRole(bv.DEFAULT_ADMIN_ROLE(), TETU_COMMUNITY_DEPLOYER_ADDRESS);

    bd.revokeRole(bd.DEFAULT_ADMIN_ROLE(), 0xa68444587ea4D3460BBc11d5aeBc1c817518d648);
    bd.revokeRole(bd.DEFAULT_ADMIN_ROLE(), 0xcc16d636dD05b52FF1D8B9CE09B09BC62b11412B);
    bd.revokeRole(bd.DEFAULT_ADMIN_ROLE(), TETU_COMMUNITY_DEPLOYER_ADDRESS);
  }
}

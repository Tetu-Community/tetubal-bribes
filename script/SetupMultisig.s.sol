// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/BribeVault.sol";
import "../src/BribeDistributor.sol";

contract SetupMultisigScript is Script {
  BribeVault bv = BribeVault(0x2dE7ab57966f7C98be4252f16350e7B185680020);
  BribeDistributor bd = BribeDistributor(0x14eFd4cecC549b90409b116Bb1b6E222FCfd54F1);

  address MULTISIG_ADDRESS = 0xB9fA147b96BbC932e549f619A448275855b9A7D9;

  function run() public {
    vm.startBroadcast();
    bv.grantRole(bv.DEFAULT_ADMIN_ROLE(), MULTISIG_ADDRESS);
    bd.grantRole(bd.DEFAULT_ADMIN_ROLE(), MULTISIG_ADDRESS);
  }
}

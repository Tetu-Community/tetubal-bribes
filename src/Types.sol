// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

library Types {
  struct Epoch {
    uint256 roundNumber;
    uint256 deadline;
  }

  struct Bribe {
    address briber;
    address gauge;
    address bribeToken;
    uint256 amount;
  }
}

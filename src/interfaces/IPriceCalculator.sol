// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IPriceCalculator {
  function getPrice(address token, address output) external view returns (uint256);
}

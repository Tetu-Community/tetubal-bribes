// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IPriceCalculator {
  function getPriceWithDefaultOutput(address token) external view returns (uint256);
}

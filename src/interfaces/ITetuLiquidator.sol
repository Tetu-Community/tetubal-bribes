// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface ITetuLiquidator {
  function getPrice(address tokenIn, address tokenOut, uint256 amount)
    external
    view
    returns (uint256);
}

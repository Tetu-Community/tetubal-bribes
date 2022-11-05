// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/interfaces/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/access/AccessControl.sol";
import "openzeppelin-contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "./interfaces/IBribeDistributor.sol";
import "./Types.sol";

contract BribeDistributor is
  IBribeDistributor,
  UUPSUpgradeable,
  AccessControl,
  Initializable,
  ReentrancyGuard
{
  using SafeERC20 for IERC20;

  // -- Storage --

  // Reserved storage space to allow for layout changes in the future.
  uint256[50] private ______gap;

  // -- Modifiers --

  function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  // -- Initializer --

  function initialize() external initializer {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  // -- Admin interface --

  /// @dev Distribute an ERC20 token to multiple recipients
  function distributeToken(
    address _token,
    address[] calldata _recipients,
    uint256[] calldata _amounts
  ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
    require(_recipients.length == _amounts.length, "BD: invalid arguments");

    for (uint256 i = 0; i < _recipients.length; i++) {
      IERC20(_token).safeTransfer(_recipients[i], _amounts[i]);
    }
  }

  function rescueToken(address _token, uint256 _amount)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    nonReentrant
  {
    IERC20(_token).safeTransfer(msg.sender, _amount);
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/interfaces/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/access/AccessControl.sol";
import "openzeppelin-contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "./interfaces/IBribeDistributor.sol";
import "./interfaces/ITetuLiquidator.sol";
import "./Types.sol";

contract BribeVault is UUPSUpgradeable, AccessControl, Initializable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using SafeERC20 for IERC20;

  // -- Events --

  event EpochCreated(bytes32 epochId, uint256 roundNumber, uint256 deadline);

  event BribeCreated(
    bytes32 epochId, bytes32 bribeId, address gauge, address token, uint256 amount
  );

  event BribeIncreased(
    bytes32 epochId, bytes32 bribeId, address gauge, address token, uint256 increasedByAmount
  );

  event BribeRejected(bytes32 epochId, bytes32 bribeId);

  event BribeWithdrawn(bytes32 epochId, bytes32 bribeId, address bribeToken, uint256 amount);

  // -- Constants --

  address constant USDC_ADDRESS = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
  address constant TETU_COMMUNITY_DOT_ETH = 0xa69E15c6aa3667484d278F19701b2DE54aa05F9b;
  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
  bytes32 public constant ALLOWLIST_DEPOSITOR_ROLE = keccak256("ALLOWLIST_DEPOSITOR_ROLE");
  uint256 constant FEE_DENOM = 1e4;

  // -- Storage --

  // Reserved storage space to allow for layout changes in the future.
  uint256[50] private ______gap;

  // Each voting round is an "Epoch". The map key can be anything, but it's
  // intended to be the keccak256 hash of the Snapshot proposal title.
  mapping(bytes32 => Types.Epoch) public epochs;

  // Each epoch can have many bribes, each bribe gets a "bribe identifier"
  // which is the hash of the (epoch, token, briber). This uses an EnumerableSet
  // which lets us manually remove a bribe if necessary.
  mapping(bytes32 => EnumerableSet.Bytes32Set) epochBribes;

  // Each bribe contains information about the bribe. The map key is the bribe
  // identifier hash.
  mapping(bytes32 => Types.Bribe) bribes;

  IBribeDistributor public bribeDistributor;
  ITetuLiquidator public tetuLiquidator;
  uint256 public minBribeAmountUsdc; // USDC, so 6 decimals of precision
  uint256 public feeBps;

  // -- Modifiers --

  modifier epochExistsAndIsCurrent(bytes32 _epochId) {
    Types.Epoch memory epoch = epochs[_epochId];
    require(epoch.roundNumber > 0, "BV: no epoch found");
    require(epoch.deadline > block.timestamp, "BV: epoch deadline passed");
    _;
  }

  modifier epochExists(bytes32 _epochId) {
    Types.Epoch memory epoch = epochs[_epochId];
    require(epoch.roundNumber > 0, "BV: no epoch found");
    _;
  }

  function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  // -- Initializer --

  function initialize(
    address _bribeDistributor,
    address _tetuLiquidator,
    uint256 _minBribeAmountUsdc,
    uint256 _feeBps
  ) external initializer {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(OPERATOR_ROLE, msg.sender);
    _setBribeDistributor(_bribeDistributor);
    _setTetuLiquidator(_tetuLiquidator);
    _setMinBribeAmountUsdc(_minBribeAmountUsdc);
    _setFeeBps(_feeBps);
  }

  // -- Read functions --

  /// @dev Get all bribes for a given epoch
  function bribesByEpoch(bytes32 _epochId)
    public
    view
    epochExists(_epochId)
    returns (Types.Bribe[] memory)
  {
    uint256 numBribes = epochBribes[_epochId].length();
    Types.Bribe[] memory returnBribes = new Types.Bribe[](numBribes);

    for (uint256 i = 0; i < numBribes; i++) {
      returnBribes[i] = bribes[epochBribes[_epochId].at(i)];
    }

    return returnBribes;
  }

  function calculateBribeId(bytes32 _epochId, address _gauge, address _token, address _briber)
    public
    pure
    returns (bytes32)
  {
    return keccak256(abi.encodePacked(_epochId, _gauge, _token, _briber));
  }

  // -- User interface --

  /// @dev Create a bribe
  function createBribe(bytes32 _epochId, address _gauge, address _token, uint256 _amount)
    external
    epochExistsAndIsCurrent(_epochId)
    nonReentrant
    returns (bytes32)
  {
    bytes32 bribeId = calculateBribeId(_epochId, _gauge, _token, msg.sender);
    require(
      bribes[bribeId].briber == address(0), "BV: bribe already exists, call increaseBribe() instead"
    );
    _validateMinBribeAmount(_token, _amount, msg.sender);
    _receiveBribeToken(_token, _amount);
    epochBribes[_epochId].add(bribeId);
    bribes[bribeId] = Types.Bribe(msg.sender, _gauge, _token, _amount);
    emit BribeCreated(_epochId, bribeId, _gauge, _token, _amount);
    return bribeId;
  }

  /// @dev Increase a bribe
  function increaseBribe(
    bytes32 _epochId,
    address _gauge,
    address _token,
    uint256 _increaseByAmount
  ) external epochExistsAndIsCurrent(_epochId) nonReentrant returns (bytes32) {
    bytes32 bribeId = calculateBribeId(_epochId, _gauge, _token, msg.sender);
    require(bribes[bribeId].briber == msg.sender, "BV: bribe does not exist");
    _receiveBribeToken(_token, _increaseByAmount);
    bribes[bribeId] =
      Types.Bribe(msg.sender, _gauge, _token, bribes[bribeId].amount + _increaseByAmount);
    emit BribeIncreased(_epochId, bribeId, _gauge, _token, _increaseByAmount);
    return bribeId;
  }

  // -- Operator interface --

  /// @dev Create an epoch
  function createEpoch(bytes32 _epochId, uint256 _roundNumber, uint256 _deadline)
    external
    onlyRole(OPERATOR_ROLE)
  {
    Types.Epoch memory epoch = epochs[_epochId];
    require(epoch.roundNumber == 0, "BV: epoch already exists");
    require(_roundNumber > 0, "BV: invalid round number");
    require(_deadline > block.timestamp, "BV: deadline must be future");
    require(_deadline < (block.timestamp + 14 days), "BV: deadline too far in future");
    epochs[_epochId] = Types.Epoch(_roundNumber, _deadline);
    emit EpochCreated(_epochId, _roundNumber, _deadline);
  }

  /// @dev Withdraw bribes for an epoch after the deadline has passed
  function withdrawBribes(bytes32 _epochId) external onlyRole(OPERATOR_ROLE) nonReentrant {
    Types.Epoch memory epoch = epochs[_epochId];
    require(epoch.roundNumber != 0, "BV: epoch does not exist");
    require(epoch.deadline < block.timestamp, "BV: deadline must be past");

    // withdraw all bribes for this epoch
    uint256 numBribes = epochBribes[_epochId].length();
    for (uint256 i = 0; i < numBribes; i++) {
      _withdrawBribe(_epochId, epochBribes[_epochId].at(i));
    }
  }

  /// @dev Reject an individual bribe and return the token to briber
  function rejectBribe(bytes32 _epochId, bytes32 _bribeId)
    external
    onlyRole(OPERATOR_ROLE)
    epochExists(_epochId)
    nonReentrant
  {
    require(bribes[_bribeId].briber != address(0), "BV: bribe does not exist");
    epochBribes[_epochId].remove(_bribeId);
    IERC20(bribes[_bribeId].bribeToken).safeTransfer(
      bribes[_bribeId].briber, bribes[_bribeId].amount
    );
    delete bribes[_bribeId];
    emit BribeRejected(_epochId, _bribeId);
  }

  // -- Admin interface --

  /// @dev Set the bribe distributor address
  function setBribeDistributor(address _bribeDistributor) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setBribeDistributor(_bribeDistributor);
  }

  /// @dev Set the price calculator address
  function setTetuLiquidator(address _tetuLiquidator) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setTetuLiquidator(_tetuLiquidator);
  }

  /// @dev Set the min bribe amount in USD with 18 decimals of precision
  function setMinBribeAmountUsdc(uint256 _minBribeAmountUsdc) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setMinBribeAmountUsdc(_minBribeAmountUsdc);
  }

  /// @dev Set the min bribe amount in USD with 18 decimals of precision
  function setFeeBps(uint256 _feeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setFeeBps(_feeBps);
  }

  /// @dev Withdraw any token to msg.sender, restricted to admin only
  function rescueToken(address _token, uint256 _amount)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    nonReentrant
  {
    IERC20(_token).safeTransfer(msg.sender, _amount);
  }

  // -- Internal --

  function _setBribeDistributor(address _bribeDistributor) internal {
    require(_bribeDistributor != address(0), "BV: bribe distributor cannot be address(0)");
    bribeDistributor = IBribeDistributor(_bribeDistributor);
  }

  function _setTetuLiquidator(address _tetuLiquidator) internal {
    require(_tetuLiquidator != address(0), "BV: price calculator cannot be address(0)");
    tetuLiquidator = ITetuLiquidator(_tetuLiquidator);
  }

  function _setMinBribeAmountUsdc(uint256 _minBribeAmountUsdc) internal {
    require(_minBribeAmountUsdc > 0, "BV: min bribe amount cannot be zero");
    minBribeAmountUsdc = _minBribeAmountUsdc;
  }

  function _setFeeBps(uint256 _feeBps) internal {
    feeBps = _feeBps;
  }

  // transfer in a token with additional balance checks to disallow transfer tax tokens
  function _receiveBribeToken(address _token, uint256 _amount) internal {
    uint256 balanceBefore = IERC20(_token).balanceOf(address(this));
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    uint256 amountReceived = IERC20(_token).balanceOf(address(this)) - balanceBefore;
    require(
      amountReceived == _amount,
      "BV: issue transferring token, transfer tax tokens are not supported"
    );
  }

  // withdraws bribe to bribe distributor
  function _withdrawBribe(bytes32 _epochId, bytes32 _bribeId) internal {
    uint256 feeAmount = bribes[_bribeId].amount * feeBps / FEE_DENOM;
    uint256 amountMinusFees = bribes[_bribeId].amount - feeAmount;

    IERC20(bribes[_bribeId].bribeToken).safeTransfer(address(bribeDistributor), amountMinusFees);

    IERC20(bribes[_bribeId].bribeToken).safeTransfer(address(TETU_COMMUNITY_DOT_ETH), feeAmount);

    emit BribeWithdrawn(_epochId, _bribeId, bribes[_bribeId].bribeToken, bribes[_bribeId].amount);
  }

  function _validateMinBribeAmount(address _token, uint256 _amount, address _briber) internal view {
    require(_amount > 0, "BV: bribe amount cannot be zero");

    // depositors on the allowlist can deposit any non-zero bribe
    if (hasRole(ALLOWLIST_DEPOSITOR_ROLE, _briber)) return;

    // other users must deposit a minimum amount in USDC
    uint256 amountInUsdc = tetuLiquidator.getPrice(_token, USDC_ADDRESS, _amount);
    require(amountInUsdc >= minBribeAmountUsdc, "BV: bribe amount in USDC too low");
  }
}

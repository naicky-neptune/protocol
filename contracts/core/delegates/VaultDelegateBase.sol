// Neptune Mutual Protocol (https://neptunemutual.com)
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "../Recoverable.sol";
import "../../interfaces/IVaultDelegate.sol";
import "../../libraries/ProtoUtilV1.sol";
import "../../libraries/CoverUtilV1.sol";
import "../../libraries/VaultLibV1.sol";
import "../../libraries/ValidationLibV1.sol";
import "../../libraries/StrategyLibV1.sol";
import "../../libraries/NTransferUtilV2.sol";

/**
 * Important: This contract is not intended to be accessed
 * by anyone/anything except individual vault contracts.
 *
 * @title Vault Delegate Base Contract
 *
 *
 * @dev The vault delegate base contract includes pre and post hooks.
 * The hooks are accessible only to vault contracts.
 *
 *
 */
abstract contract VaultDelegateBase is IVaultDelegate, Recoverable {
  using ProtoUtilV1 for bytes;
  using ProtoUtilV1 for IStore;
  using VaultLibV1 for IStore;
  using ValidationLibV1 for IStore;
  using RoutineInvokerLibV1 for IStore;
  using StoreKeyUtil for IStore;
  using StrategyLibV1 for IStore;
  using CoverUtilV1 for IStore;
  using NTransferUtilV2 for IERC20;

  /**
   * @dev Constructs this contract
   * @param store Provide the store contract instance
   */
  constructor(IStore store) Recoverable(store) {} // solhint-disable-line

  /**
   * @dev This hook runs before `transferGovernance` implementation on vault(s).
   *
   *
   * Note:
   *
   * - Governance transfers are allowed via claims processor contract only.
   * - This function's caller must be the vault of the specified coverKey.
   *
   * @param caller Enter your msg.sender value.
   * @param coverKey Provide your vault's cover key.
   *
   * @return stablecoin Returns address of the protocol stablecoin if the hook validation passes.
   */
  function preTransferGovernance(
    address caller,
    bytes32 coverKey,
    address, /*to*/
    uint256 /*amount*/
  ) external override nonReentrant returns (address stablecoin) {
    // @suppress-zero-value-check This function does not transfer any values
    s.mustNotBePaused();
    s.mustBeProtocolMember(caller);
    s.mustBeProtocolMember(msg.sender);
    s.senderMustBeVaultContract(coverKey);
    s.callerMustBeClaimsProcessorContract(caller);

    stablecoin = s.getStablecoin();
  }

  /**
   * @dev This hook runs after `transferGovernance` implementation on vault(s)
   * and performs cleanup and/or validation if needed.
   *
   * @param coverKey Provide your vault's cover key.
   *
   */
  function postTransferGovernance(
    address caller,
    bytes32 coverKey,
    address, /*to*/
    uint256 /*amount*/
  ) external view override {
    s.mustNotBePaused();
    s.mustBeProtocolMember(caller);
    s.mustBeProtocolMember(msg.sender);
    s.senderMustBeVaultContract(coverKey);
    s.callerMustBeClaimsProcessorContract(caller);
    // @suppress-reentrancy The `postTransferGovernance` hook is executed under the same context of `preTransferGovernance`.
    // @note: do not update state and liquidity since `transferGovernance` is an internal contract-only function
  }

  /**
   * @dev This hook runs before `transferToStrategy` implementation on vault(s)
   *
   * Note:
   *
   * - Transfers are allowed to exact strategy contracts only
   * where the strategy can perform lending.
   *
   * @param caller Enter your msg.sender value
   * @param token Provide the ERC20 token you'd like to transfer to the given strategy
   * @param coverKey Provide your vault's cover key
   * @param strategyName Enter the strategy name
   * @param amount Enter the amount to transfer
   *
   */
  function preTransferToStrategy(
    address caller,
    IERC20 token,
    bytes32 coverKey,
    bytes32 strategyName,
    uint256 amount
  ) external override nonReentrant {
    // @suppress-zero-value-check Checked
    s.mustNotBePaused();
    s.mustBeProtocolMember(caller);
    s.mustBeProtocolMember(msg.sender);
    s.senderMustBeVaultContract(coverKey);
    s.callerMustBeSpecificStrategyContract(caller, strategyName);

    s.preTransferToStrategyInternal(token, coverKey, strategyName, amount);
  }

  /**
   * @dev This hook runs after `transferToStrategy` implementation on vault(s)
   * and performs cleanup and/or validation if needed.
   *
   * @param caller Enter your msg.sender value
   * @param coverKey Enter the coverKey
   * @param strategyName Enter the strategy name
   *
   */
  function postTransferToStrategy(
    address caller,
    IERC20, /*token*/
    bytes32 coverKey,
    bytes32 strategyName,
    uint256 /*amount*/
  ) external view override {
    s.mustNotBePaused();
    s.mustBeProtocolMember(caller);
    s.mustBeProtocolMember(msg.sender);
    s.senderMustBeVaultContract(coverKey);
    s.callerMustBeSpecificStrategyContract(caller, strategyName);
    // @suppress-reentrancy The `postTransferToStrategy` hook is executed under the same context of `preTransferToStrategy`.
    // @note: do not update state and liquidity since `transferToStrategy` itself is a part of the state update
  }

  /**
   * @dev This hook runs before `receiveFromStrategy` implementation on vault(s)
   *
   * Note:
   *
   * - Access is allowed to exact strategy contracts only
   * - The caller must be the strategy contract
   * - msg.sender must be the correct vault contract
   *
   * @param caller Enter your msg.sender value
   * @param coverKey Provide your vault's cover key
   * @param strategyName Enter the strategy name
   *
   */
  function preReceiveFromStrategy(
    address caller,
    IERC20, /*token*/
    bytes32 coverKey,
    bytes32 strategyName,
    uint256 /*amount*/
  ) external override nonReentrant {
    // @suppress-zero-value-check This function does not transfer any tokens
    s.mustNotBePaused();
    s.mustBeProtocolMember(caller);
    s.mustBeProtocolMember(msg.sender);
    s.senderMustBeVaultContract(coverKey);
    s.callerMustBeSpecificStrategyContract(caller, strategyName);
  }

  /**
   * @dev This hook runs after `receiveFromStrategy` implementation on vault(s)
   * and performs cleanup and/or validation if needed.
   *
   * @param caller Enter your msg.sender value
   * @param token Enter the token your vault received from strategy
   * @param coverKey Enter the coverKey
   * @param strategyName Enter the strategy name
   * @param amount Enter the amount received
   *
   */
  function postReceiveFromStrategy(
    address caller,
    IERC20 token,
    bytes32 coverKey,
    bytes32 strategyName,
    uint256 amount
  ) external override returns (uint256 income, uint256 loss) {
    // @suppress-zero-value-check This call does not perform any transfers
    s.mustNotBePaused();
    s.mustBeProtocolMember(caller);
    s.mustBeProtocolMember(msg.sender);
    s.senderMustBeVaultContract(coverKey);
    s.callerMustBeSpecificStrategyContract(caller, strategyName);

    (income, loss) = s.postReceiveFromStrategyInternal(token, coverKey, strategyName, amount);
    // @suppress-reentrancy The `postReceiveFromStrategy` hook is executed under the same context of `preReceiveFromStrategy`.
    // @note: do not update state and liquidity since `receiveFromStrategy` itself is a part of the state update
  }

  /**
   * @dev This hook runs before `addLiquidity` implementation on vault(s)
   *
   * Note:
   *
   * - msg.sender must be correct vault contract
   *
   * @param coverKey Enter the cover key
   * @param amount Enter the amount of liquidity token to supply.
   * @param npmStakeToAdd Enter the amount of NPM token to stake.
   */
  function preAddLiquidity(
    address caller,
    bytes32 coverKey,
    uint256 amount,
    uint256 npmStakeToAdd
  ) external override nonReentrant returns (uint256 podsToMint, uint256 previousNpmStake) {
    // @suppress-zero-value-check This call does not transfer any tokens
    s.mustNotBePaused();
    s.mustBeProtocolMember(msg.sender);
    s.senderMustBeVaultContract(coverKey);
    s.mustHaveNormalCoverStatus(coverKey);
    VaultLibV1.mustNotExceedStablecoinThreshold(s, amount);
    VaultLibV1.mustNotExceedNpmThreshold(amount);

    address pod = msg.sender;
    (podsToMint, previousNpmStake) = s.preAddLiquidityInternal(coverKey, pod, caller, amount, npmStakeToAdd);
  }

  /**
   * @dev This hook runs after `addLiquidity` implementation on vault(s)
   * and performs cleanup and/or validation if needed.
   *
   * @param coverKey Enter the coverKey
   *
   */
  function postAddLiquidity(
    address, /*caller*/
    bytes32 coverKey,
    uint256, /*amount*/
    uint256 /*npmStakeToAdd*/
  ) external override {
    // @suppress-zero-value-check This function does not transfer any tokens
    s.mustNotBePaused();
    s.mustBeProtocolMember(msg.sender);
    s.senderMustBeVaultContract(coverKey);
    s.mustHaveNormalCoverStatus(coverKey);
    s.updateStateAndLiquidity(coverKey);

    // @suppress-reentrancy The `postAddLiquidity` hook is executed under the same context of `preAddLiquidity`.
  }

  /**
   * @dev This implemention enables liquidity manages to
   * accrue interests on a vault before withdrawals are allowed.
   *
   * Note:
   *
   * - Caller must be a liquidity manager
   * - msg.sender must the correct vault contract
   *
   * @param caller Enter your msg.sender value
   * @param coverKey Provide your vault's cover key
   */
  function accrueInterestImplementation(address caller, bytes32 coverKey) external override {
    s.mustNotBePaused();
    s.senderMustBeVaultContract(coverKey);
    AccessControlLibV1.callerMustBeLiquidityManager(s, caller);

    s.accrueInterestInternal(coverKey);
  }

  /**
   * @dev This hook runs before `removeLiquidity` implementation on vault(s)
   *
   * Note:
   *
   * - msg.sender must be the correct vault contract
   * - Must have at couple of block height offset following a deposit.
   * - Must be done during withdrawal period
   * - Must have no balance in strategies
   * - Cover status should be normal
   * - Interest should already be accrued
   *
   * @param caller Enter your msg.sender value
   * @param coverKey Enter the cover key
   * @param podsToRedeem Enter the amount of pods to redeem
   * @param npmStakeToRemove Enter the amount of NPM stake to remove.
   * @param exit If this is set to true, LPs can remove their entire NPM stake during a withdrawal period. No restriction.
   */
  function preRemoveLiquidity(
    address caller,
    bytes32 coverKey,
    uint256 podsToRedeem,
    uint256 npmStakeToRemove,
    bool exit
  ) external override nonReentrant returns (address stablecoin, uint256 stablecoinToRelease) {
    // @suppress-zero-value-check This call does not transfer any tokens
    s.mustNotBePaused();
    s.mustBeProtocolMember(msg.sender);
    s.senderMustBeVaultContract(coverKey);
    s.mustMaintainBlockHeightOffset(coverKey);
    s.mustHaveNormalCoverStatus(coverKey);
    s.mustBeDuringWithdrawalPeriod(coverKey);
    s.mustHaveNoBalanceInStrategies(coverKey, stablecoin);
    s.mustBeAccrued(coverKey);

    address pod = msg.sender; // The sender is vault contract
    return s.preRemoveLiquidityInternal(coverKey, pod, caller, podsToRedeem, npmStakeToRemove, exit);
  }

  /**
   * @dev This hook runs after `removeLiquidity` implementation on vault(s)
   * and performs cleanup and/or validation if needed.
   *
   * @param coverKey Enter the coverKey
   *
   */
  function postRemoveLiquidity(
    address, /*caller*/
    bytes32 coverKey,
    uint256, /*podsToRedeem*/
    uint256, /*npmStakeToRemove*/
    bool /*exit*/
  ) external override {
    s.mustBeProtocolMember(msg.sender);
    s.senderMustBeVaultContract(coverKey);
    s.updateStateAndLiquidity(coverKey);

    // @suppress-reentrancy The `postRemoveLiquidity` hook is executed under the same context as `preRemoveLiquidity`.
  }

  /**
   * @dev Calculates the amount of PODs to mint for the given amount of liquidity
   */
  function calculatePodsImplementation(bytes32 coverKey, uint256 stablecoinIn) external view override returns (uint256) {
    s.senderMustBeVaultContract(coverKey);

    address pod = msg.sender;

    return s.calculatePodsInternal(coverKey, pod, stablecoinIn);
  }

  /**
   * @dev Calculates the amount of stablecoins to receive for the given amount of PODs to redeem
   */
  function calculateLiquidityImplementation(bytes32 coverKey, uint256 podsToBurn) external view override returns (uint256) {
    s.senderMustBeVaultContract(coverKey);
    address pod = msg.sender;
    return s.calculateLiquidityInternal(coverKey, pod, podsToBurn);
  }

  /**
   * @dev Returns the stablecoin balance of this vault
   * This also includes amounts lent out in lending strategies by this vault
   */
  function getStablecoinBalanceOfImplementation(bytes32 coverKey) external view override returns (uint256) {
    s.senderMustBeVaultContract(coverKey);
    return s.getStablecoinOwnedByVaultInternal(coverKey);
  }

  /**
   * @dev Gets information of a given vault by the cover key
   * @param coverKey Specify cover key to obtain the info of.
   * @param you The address for which the info will be customized
   * @param values[0] totalPods --> Total PODs in existence
   * @param values[1] balance --> Stablecoins held in the vault
   * @param values[2] extendedBalance --> Stablecoins lent outside of the protocol
   * @param values[3] totalReassurance -- > Total reassurance for this cover
   * @param values[4] myPodBalance --> Your POD Balance
   * @param values[5] myShare --> My share of the liquidity pool (in stablecoin)
   * @param values[6] withdrawalOpen --> The timestamp when withdrawals are opened
   * @param values[7] withdrawalClose --> The timestamp when withdrawals are closed again
   */
  function getInfoImplementation(bytes32 coverKey, address you) external view override returns (uint256[] memory values) {
    s.senderMustBeVaultContract(coverKey);
    address pod = msg.sender;
    return s.getInfoInternal(coverKey, pod, you);
  }

  /**
   * @dev Version number of this contract
   */
  function version() external pure override returns (bytes32) {
    return "v0.1";
  }

  /**
   * @dev Name of this contract
   */
  function getName() external pure override returns (bytes32) {
    return ProtoUtilV1.CNAME_VAULT_DELEGATE;
  }
}

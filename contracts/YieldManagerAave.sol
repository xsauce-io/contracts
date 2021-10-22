// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "hardhat/console.sol";

import "./interfaces/IYieldManager.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IAaveIncentivesController.sol";
import "./abstract/AccessControlledAndUpgradeable.sol";

/** @title YieldManagerAave
  @notice contract is used to manage the yield generated by the underlying tokens.
  YieldManagerAave is an implementation of a yield manager that earns APY from the Aave protocol.
  Each fund's payment token (such as DAI) has a corresponding aToken (such as aDAI) that
  continuously accrues interest based on a lend/borrow liquidity ratio.
  @dev https://docs.aave.com/portal/
  */
contract YieldManagerAave is IYieldManager, AccessControlledAndUpgradeable {
  /*╔═════════════════════════════╗
    ║          VARIABLES          ║
    ╚═════════════════════════════╝*/

  /// @notice address of longShort contract
  address public longShort;
  /// @notice address of treasury contract - this is the address that can claim aave incentives rewards
  address public treasury;

  /// @notice boolean to prevent markets using an already initialized market
  bool public isInitialized;

  /// @notice The payment token the yield manager supports
  /// @dev DAI token
  IERC20 public paymentToken;
  /// @notice The token representing the interest accruing payment token position from Aave
  /// @dev ADAI token
  IERC20Upgradeable public aToken;
  /// @notice The specific Aave lending pool address provider contract
  ILendingPoolAddressesProvider public lendingPoolAddressesProvider;
  /// @notice The specific Aave incentives controller contract
  IAaveIncentivesController public aaveIncentivesController;

  /// @dev An aave specific referralCode that has been a depricated feature. This will be set to 0 for "no referral" at deployment
  uint16 referralCode;

  /// @notice distributed yield not yet transferred to the treasury
  uint256 public override totalReservedForTreasury;

  /// @dev This value will likely remain zero forever. It exists to handle the rare edge case that Aave doesn't have enough liquidity for a withdrawal.
  ///      In this case this variable would keep track of that so that the withdrawal can happen after the fact when liquidity becomes available.
  uint256 public amountReservedInCaseOfInsufficientAaveLiquidity;

  /*╔═════════════════════════════╗
    ║          MODIFIERS          ║
    ╚═════════════════════════════╝*/

  /// @dev only allow longShort contract to execute modified functions
  modifier longShortOnly() {
    require(msg.sender == longShort, "Not longShort");
    _;
  }

  /*╔═════════════════════════════╗
    ║       CONTRACT SET-UP       ║
    ╚═════════════════════════════╝*/

  function internalInitialize(
    address _longShort,
    address _treasury,
    address _paymentToken,
    address _aToken,
    address _lendingPoolAddressesProvider,
    address _aaveIncentivesController,
    uint16 _aaveReferralCode,
    address _admin
  ) internal initializer {
    require(
      _longShort != address(0) &&
        _treasury != address(0) &&
        _paymentToken != address(0) &&
        _aToken != address(0) &&
        _lendingPoolAddressesProvider != address(0) &&
        _aaveIncentivesController != address(0) &&
        _admin != address(0)
    );

    longShort = _longShort;
    treasury = _treasury;

    _AccessControlledAndUpgradeable_init(_admin);

    referralCode = _aaveReferralCode;

    paymentToken = IERC20(_paymentToken);
    aToken = IERC20Upgradeable(_aToken);
    lendingPoolAddressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
    aaveIncentivesController = IAaveIncentivesController(_aaveIncentivesController);
  }

  /**
    @notice Constructor for initializing the aave yield manager with a given payment token and corresponding Aave contracts
    @param _longShort address of the longShort contract
    @param _treasury address of the treasury contract
    @param _paymentToken address of the payment token
    @param _aToken address of the interest accruing token linked to the payment token
    @param _lendingPoolAddressesProvider address of the aave lending pool address provider contract
    @param _aaveReferralCode unique code for aave referrals
    @param _admin admin for the contract
    @dev referral code will be set to 0, depricated Aave feature
  */
  function initialize(
    address _longShort,
    address _treasury,
    address _paymentToken,
    address _aToken,
    address _lendingPoolAddressesProvider,
    address _aaveIncentivesController,
    uint16 _aaveReferralCode,
    address _admin
  ) external initializer {
    internalInitialize(
      _longShort,
      _treasury,
      _paymentToken,
      _aToken,
      _lendingPoolAddressesProvider,
      _aaveIncentivesController,
      _aaveReferralCode,
      _admin
    );

    // Approve tokens for aave lending pool maximally.
    IERC20(_paymentToken).approve(
      ILendingPoolAddressesProvider(_lendingPoolAddressesProvider).getLendingPool(),
      type(uint256).max
    );
  }

  function updateLatestLendingPoolAddress() external {
    IERC20(paymentToken).approve(lendingPoolAddressesProvider.getLendingPool(), type(uint256).max);
  }

  /*╔════════════════════════╗
    ║     IMPLEMENTATION     ║
    ╚════════════════════════╝*/

  /**
   @notice Allows the LongShort contract to deposit tokens into the aave pool
   @param amount Amount of payment token to deposit
  */
  function depositPaymentToken(uint256 amount) external override longShortOnly {
    // If amountReservedInCaseOfInsufficientAaveLiquidity isn't zero, then efficiently net the difference between the amount
    //    It basically always be zero besides extreme and unlikely situations with aave.
    if (amountReservedInCaseOfInsufficientAaveLiquidity != 0) {
      if (amountReservedInCaseOfInsufficientAaveLiquidity >= amount) {
        amountReservedInCaseOfInsufficientAaveLiquidity -= amount;
        // Return early, nothing to deposit into the lending pool
        return;
      } else {
        amount -= amountReservedInCaseOfInsufficientAaveLiquidity;
        amountReservedInCaseOfInsufficientAaveLiquidity = 0;
      }
    }

    ILendingPool(lendingPoolAddressesProvider.getLendingPool()).deposit(
      address(paymentToken),
      amount,
      address(this),
      referralCode
    );
  }

  /// @notice Allows the LongShort pay out a user from tokens already withdrawn from Aave
  /// @param user User to recieve the payout
  /// @param amount Amount of payment token to pay to user
  function transferPaymentTokensToUser(address user, uint256 amount)
    external
    override
    longShortOnly
  {
    try paymentToken.transfer(user, amount) returns (bool transferSuccess) {
      if (transferSuccess) {
        // If the transfer is successful return early, otherwise try pay the user out with the amountReservedInCaseOfInsufficientAaveLiquidity
        return;
      }
    } catch {}

    amountReservedInCaseOfInsufficientAaveLiquidity -= amount;

    // If this reverts (ie aave unable to make payout), then the whole transaction will revert. User will have to wait until sufficient liquidity available.
    ILendingPool(lendingPoolAddressesProvider.getLendingPool()).withdraw(
      address(paymentToken),
      amount,
      user
    );
  }

  /// @notice Allows the LongShort contract to redeem aTokens for the payment token
  /// @param amount Amount of payment token to withdraw
  /// @dev This will update the amountReservedInCaseOfInsufficientAaveLiquidity if not enough liquidity is avaiable on aave.
  ///      This means that our system can continue to operate even if there is insufficient liquidity in Aave for any reason.
  function removePaymentTokenFromMarket(uint256 amount) external override longShortOnly {
    try
      ILendingPool(lendingPoolAddressesProvider.getLendingPool()).withdraw(
        address(paymentToken),
        amount,
        address(this)
      )
    {} catch {
      // In theory we should only catch `VL_CURRENT_AVAILABLE_LIQUIDITY_NOT_ENOUGH` errors.
      // Safe to revert on all errors, if aave completely blocks withdrawals the amountReservedInCaseOfInsufficientAaveLiquidity can grow until it is fixed without problems.
      amountReservedInCaseOfInsufficientAaveLiquidity += amount;
    }
  }

  /**
    @notice Allows for withdrawal of aave rewards to the treasury contract
    @dev This is specifically implemented to allow withdrawal of aave reward wMatic tokens accrued
  */
  function claimAaveRewardsToTreasury() external {
    IAaveIncentivesController _aaveIncentivesController = IAaveIncentivesController(
      aaveIncentivesController
    );
    uint256 amount = _aaveIncentivesController.getUserUnclaimedRewards(address(this));

    address[] memory aTokenAddresses = new address[](1);
    aTokenAddresses[0] = address(aToken);

    _aaveIncentivesController.claimRewards(aTokenAddresses, amount, treasury);

    emit ClaimAaveRewardTokenToTreasury(amount);
  }

  /**
    @notice Calculates and updates the yield allocation to the treasury and the market
    @dev treasuryPercent = 1 - marketPercent
    @param totalValueRealizedForMarket total value of long and short side of the market
    @param treasuryYieldPercent_e18 Percentage of yield in base 1e18 that is allocated to the treasury
    @return The market allocation of the yield
  */
  function distributeYieldForTreasuryAndReturnMarketAllocation(
    uint256 totalValueRealizedForMarket,
    uint256 treasuryYieldPercent_e18
  ) external override longShortOnly returns (uint256) {
    uint256 totalHeld = aToken.balanceOf(address(this));
    uint256 _totalReservedForTreasury = totalReservedForTreasury;

    uint256 totalRealized = totalValueRealizedForMarket +
      _totalReservedForTreasury +
      amountReservedInCaseOfInsufficientAaveLiquidity;

    if (totalRealized == totalHeld) {
      return 0;
    }

    // will revert in case totalRealized > totalHeld which should never occur since yield is always possitive with aave.
    uint256 unrealizedYield = totalHeld - totalRealized;

    uint256 amountForTreasury = (unrealizedYield * treasuryYieldPercent_e18) / 1e18;
    uint256 amountForMarketIncentives = unrealizedYield - amountForTreasury;

    totalReservedForTreasury = _totalReservedForTreasury + amountForTreasury;

    emit YieldDistributed(unrealizedYield, treasuryYieldPercent_e18);

    return amountForMarketIncentives;
  }

  /// @notice Withdraw treasury allocated accrued yield from the lending pool to the treasury contract
  function withdrawTreasuryFunds() external override {
    uint256 amountToWithdrawForTreasury = totalReservedForTreasury;
    totalReservedForTreasury = 0;

    // Redeem aToken for payment tokens.
    ILendingPool(lendingPoolAddressesProvider.getLendingPool()).withdraw(
      address(paymentToken),
      amountToWithdrawForTreasury,
      treasury
    );

    emit WithdrawTreasuryFunds();
  }

  /// @notice Initializes a specific yield manager to a given market
  function initializeForMarket() external override longShortOnly {
    require(!isInitialized, "Yield Manager is already in use");
    isInitialized = true;
  }
}

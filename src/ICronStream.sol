// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// PoolKey will come from v4-core once installed:
// import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface ICronStream {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a pool is added to the whitelist
    event PoolAuthorized(bytes32 indexed poolId);

    /// @notice Emitted when yield is successfully pushed to an LP wallet
    event YieldDistributed(bytes32 indexed poolId, address indexed lp, uint256 amount);

    /// @notice Emitted when an LP transfer fails (KYC revoked, sanctions, blacklist)
    /// The amount is held in escrow — LP share is not lost
    event YieldEscrowed(address indexed lp, uint256 amount, string reason);

    /// @notice Emitted when escrowed funds are released to a verified clean address
    event EscrowReleased(address indexed originalLp, address indexed destination, uint256 amount);

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Whitelist a pool before it can bind to the hook
    /// Only callable by the protocol admin (onlyOwner)
    /// Must be called before pool initialization — hook binding is immutable
    function authorizePool(bytes32 poolId) external;

    // -------------------------------------------------------------------------
    // Distribution
    // -------------------------------------------------------------------------

    /// @notice Trigger yield distribution for a whitelisted pool
    /// Permissionless — any caller is reimbursed for gas within the same transaction
    /// Detects rebase surplus, distributes pro-rata to all LPs, escrows failed transfers
    function distributeYield(bytes32 poolId) external;

    // -------------------------------------------------------------------------
    // Escrow
    // -------------------------------------------------------------------------

    /// @notice Release escrowed funds for a previously sanctioned LP
    /// Only callable by admin after the LP has resolved their compliance status
    /// Funds are sent to a verified clean destination, not back to the original address
    function releaseEscrow(address originalLp, address destination) external;

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /// @notice Returns true if a pool is authorized to use the hook
    function isAuthorizedPool(bytes32 poolId) external view returns (bool);

    /// @notice Returns an LP's current liquidity share in a pool
    function lpLiquidity(bytes32 poolId, address lp) external view returns (uint128);

    /// @notice Returns the total liquidity tracked across all LPs in a pool
    function totalLiquidity(bytes32 poolId) external view returns (uint128);

    /// @notice Returns the escrowed yield balance for a given address
    function escrowedYield(address lp) external view returns (uint256);
}

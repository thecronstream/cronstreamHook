// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";
import {CronStreamHook} from "../src/CronStreamHook.sol";

contract DeployCronStream is Script {
    // Reward rate: 1e6 USDC-wei per unit of liquidity per second
    uint256 constant REWARD_RATE = 1e6;

    // Initial pool price — 1:1 ratio (sqrtPriceX96 for price = 1)
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    // Pool fee — 0.30%
    uint24 constant FEE = 3000;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy mock tokens (tokenA as the "pool token", tokenB as reward USDC stand-in)
        MockERC20 tokenA = new MockERC20("Token A", "TKNA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKNB", 18);
        MockERC20 rewardToken = new MockERC20("Mock USDC", "mUSDC", 6);

        console.log("TokenA:     ", address(tokenA));
        console.log("TokenB:     ", address(tokenB));
        console.log("RewardToken:", address(rewardToken));

        // Sort tokens so currency0 < currency1 (v4 requirement)
        (Currency currency0, Currency currency1) = address(tokenA) < address(tokenB)
            ? (Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)))
            : (Currency.wrap(address(tokenB)), Currency.wrap(address(tokenA)));

        // 2. Get PoolManager address for Base Sepolia
        IPoolManager poolManager = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));
        console.log("PoolManager:", address(poolManager));

        // 3. Deploy CronStreamHook at an address with the correct flag bits
        //    afterAddLiquidity (bit 10) | afterRemoveLiquidity (bit 8)
        uint160 flags = uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG);
        CronStreamHook hook = new CronStreamHook{salt: _findSalt(flags, deployer, address(poolManager), address(rewardToken))}(
            poolManager,
            address(rewardToken),
            REWARD_RATE
        );

        console.log("CronStreamHook:", address(hook));

        // 4. Set up reward vault — deployer funds it and approves the hook
        rewardToken.mint(deployer, 1_000_000e6);
        rewardToken.approve(address(hook), type(uint256).max);
        hook.setRewardVault(deployer);

        console.log("RewardVault set to deployer:", deployer);

        // 5. Initialize the pool
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        poolManager.initialize(poolKey, SQRT_PRICE_1_1);

        console.log("Pool initialized.");
        console.log("PoolKey.fee:", FEE);

        vm.stopBroadcast();

        // Print summary
        console.log("\n--- Deployment Summary ---");
        console.log("Network chainId:", block.chainid);
        console.log("CronStreamHook:", address(hook));
        console.log("RewardToken (mUSDC):", address(rewardToken));
        console.log("TokenA:", address(tokenA));
        console.log("TokenB:", address(tokenB));
        console.log("RewardVault:", deployer);
    }

    // Mine a CREATE2 salt so the hook lands at an address with the required flag bits
    function _findSalt(uint160 flags, address deployer, address poolManager, address rewardToken)
        internal pure returns (bytes32)
    {
        bytes memory creationCode = abi.encodePacked(
            type(CronStreamHook).creationCode,
            abi.encode(poolManager, rewardToken, uint256(1e6))
        );
        bytes32 initCodeHash = keccak256(creationCode);

        for (uint256 i = 0; i < 100_000; i++) {
            bytes32 salt = bytes32(i);
            address predicted = address(uint160(uint256(keccak256(
                abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)
            ))));
            if (uint160(predicted) & flags == flags) {
                return salt;
            }
        }
        revert("No valid salt found in range");
    }

    function _mineHookAddress(uint160 flags, address deployer, address poolManager, address rewardToken)
        internal pure returns (address)
    {
        bytes memory creationCode = abi.encodePacked(
            type(CronStreamHook).creationCode,
            abi.encode(poolManager, rewardToken, uint256(1e6))
        );
        bytes32 initCodeHash = keccak256(creationCode);

        for (uint256 i = 0; i < 100_000; i++) {
            bytes32 salt = bytes32(i);
            address predicted = address(uint160(uint256(keccak256(
                abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)
            ))));
            if (uint160(predicted) & flags == flags) {
                return predicted;
            }
        }
        revert("No valid address found");
    }
}

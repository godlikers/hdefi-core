// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

import "./modules/Configable.sol";
import "./modules/ConfigNames.sol";
import "./interface/IERC20.sol";
import './libraries/TransferHelper.sol';

interface IAAAAShare {
    function getProductivity(address user) external view returns (uint, uint);
    function stakeTo(uint amount, address user) external;
}

/// @title Voting with delegation.
contract AAAABallot is Configable {
    // This declares a new complex type which will
    // be used for variables later.
    // It will represent a single voter.
    struct Voter {
        uint weight; // weight is accumulated by delegation
        bool voted;  // if true, that person already voted
        uint vote;   // index of the voted proposal 0 YES, 1 NO
        bool claimed; // already claimed reward
    }
    
    uint private constant YES = 0;
    uint private constant NO = 1;
    
    bytes32 public name;
    address public pool; // pool address or address(0)
    address public creator;
    uint    public value;
    mapping(uint => uint) public proposals;
    uint    public createdBlock;
    uint    public createdTime;
    string  public subject;
    string  public content;
    uint    public total;
    uint    public reward;
    bool    public executed;

    // This declares a state variable that
    // stores a `Voter` struct for each possible address.
    mapping(address => Voter) public voters;

    event Voted(address indexed _user, uint _index, uint _weight);
    event Claimed(address indexed _user, address indexed _token, uint _reward);
    event Executed(address indexed _user);
    
    constructor () public {
        createdTime = block.timestamp;
        createdBlock = block.number;
    }
    
    function initialize(address _creator, address _pool, bytes32 _name, uint _value, uint _reward, string calldata _subject, string calldata _content) onlyFactory external {
        creator = _creator;
        content = _content;
        subject = _subject;
        value = _value;
        pool = _pool;
        reward = _reward;
        name = _name;
    }

    /// Give your vote (including votes delegated to you)
    /// to proposal `proposals[proposal].name`.
    function vote(address _user, uint _index) onlyGovernor external {
        require(_index == YES || _index == NO, "BALLOT: INVALID INDEX");
        require(!end(), "BALLOT: ALREADY END");
        
        (uint amount, ) = IAAAAShare(IConfig(config).share()).getProductivity(_user);
        Voter storage sender = voters[_user];
        require(!sender.voted, "Already voted.");
        sender.voted = true;
        sender.vote = _index;
        sender.weight = amount;
        
        proposals[_index] += amount;
        total += amount;
        emit Voted(_user, _index, amount);
    }

    function execute(address _user) onlyGovernor external {
        executed = true;
        emit Executed(_user);
    }
    
    function claim() external {
        require(voters[msg.sender].claimed == false, "Already claimed.");
        require(voters[msg.sender].weight > 0, "Not vote yet.");
        require(reward > 0, "Nothing to claim");
        require(end(), "Vote not end.");
        uint userReward = voters[msg.sender].weight * reward / total;
        
        TransferHelper.safeTransfer(IConfig(config).token(), msg.sender, userReward);
        voters[msg.sender].claimed = true;
        emit Claimed(msg.sender, IConfig(config).token(), userReward);
    }
    
    function end() public view returns (bool) {
        return block.number > createdBlock + IConfig(config).getValue(ConfigNames.PROPOSAL_VOTE_DURATION);
    }

    /// @dev Computes the winning proposal taking all
    /// previous votes into account.
    function pass() external view returns (bool) {
        return proposals[YES] > proposals[NO];
    }
    
    function expire() external view returns (bool) {
        return block.number > createdBlock + IConfig(config).getValue(ConfigNames.PROPOSAL_VOTE_DURATION) + IConfig(config).getValue(ConfigNames.PROPOSAL_EXECUTE_DURATION);
    }
}
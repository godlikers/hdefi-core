// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;
import './libraries/SafeMath.sol';
import './libraries/TransferHelper.sol';
import './modules/Configable.sol';
import './modules/ConfigNames.sol';

interface IAAAAFactory {
    function createBallot(address _creator, address _pool, 
        bytes32 _name, uint _value, uint _reward, string calldata _subject, string calldata _content, bytes calldata _bytecode) external returns (address ballot);
}

interface IAAAABallot {
    function vote(address _user, uint _index) external;
    function execute(address _user) external;
    function executed() external returns (bool);
    function end() external returns (bool);
    function pass() external returns (bool);
    function expire() external returns (bool);
    function value() external returns (uint);
    function name() external returns (bytes32);
    function pool() external returns (address);
}

interface IAAAAMint {
    function changeInterestRatePerBlock(uint value) external returns (bool);
    function sync() external;
}

interface IAAAAShare {
    function lockStake(address _user) external;
}

contract AAAAGovernance is Configable {
    function createProposal(address _pool, bytes32 _key, uint _value, string calldata _subject, string calldata _content, bytes calldata _bytecode) external {
        _checkValid(_pool, _key, _value);
        uint cost = IConfig(config).getValue(ConfigNames.PROPOSAL_CREATE_COST);
        address token = IConfig(config).token();
        address ballot = IAAAAFactory(IConfig(config).factory()).createBallot(msg.sender, _pool, _key, _value, cost, _subject, _content, _bytecode);
        if(cost > 0) {
            TransferHelper.safeTransferFrom(token, msg.sender, address(this), cost);
            TransferHelper.safeTransfer(token, ballot, cost);
        }
    }

    function voteProposal(address _ballot, uint _index) external {
        IAAAABallot(_ballot).vote(msg.sender, _index);
        IAAAAShare(IConfig(config).share()).lockStake(msg.sender);
    }
    
    function executeProposal(address _ballot) external {
        require(IAAAABallot(_ballot).end(), "Vote not end");
        require(!IAAAABallot(_ballot).expire(), "Vote expire");
        require(IAAAABallot(_ballot).pass(), "Vote not pass");
        require(!IAAAABallot(_ballot).executed(), "Vote executed");
        
        bytes32 key = IAAAABallot(_ballot).name();
        uint value = IAAAABallot(_ballot).value();
        address pool = IAAAABallot(_ballot).pool();
        _checkValid(pool, key, value);
        
        if(key == ConfigNames.MINT_AMOUNT_PER_BLOCK) {
            IConfig(config).setValue(key, value);
            IAAAAMint(IConfig(config).mint()).sync();
        } else if(pool == address(0)) {
            IConfig(config).setValue(key, value);
        } else {
            IConfig(config).setPoolValue(pool, key, value);
        }
        IAAAABallot(_ballot).execute(msg.sender);
    }
    
    function _checkValid(address _pool, bytes32 _key, uint _value) view internal {
        (uint min, uint max, uint span, uint value) = _pool == address(0) ? IConfig(config).getParams(_key): IConfig(config).getPoolParams(_pool, _key);
        
        require(_value <= max && _value >= min, "INVALID VALUE");
        require(_value != value, "Same VALUE");
        require(value + span >= _value && _value + span >= value, "INVALID SPAN");
    }
}
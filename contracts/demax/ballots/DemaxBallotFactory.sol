pragma solidity >=0.6.6;

import "./DemaxBallot.sol";

contract DemaxBallotFactory {
    mapping (address => address) tokens;
    mapping (bytes32 => address) keys;

    event Created(address indexed proposer, address indexed ballotAddr, uint createTime);

    constructor () public {
    }

    function _create(address _proposer, uint _value, uint _endBlockNumber, string memory _subject, string memory _content) internal returns (address) {
        require(_value >= 0, 'DemaxBallotFactory: INVALID_PARAMTERS');
        address ballotAddr = address(
            new DemaxBallot()
        );
        DemaxBallot(ballotAddr).initialize(_proposer, _value, _endBlockNumber, msg.sender, _subject, _content);
        emit Created(_proposer, ballotAddr, block.timestamp);
        return ballotAddr;
    }

    function _check(address _ballot) internal view returns (bool) {
        if(block.number >= DemaxBallot(_ballot).endBlockNumber()) return true;
        if (DemaxBallot(_ballot).ended() == false) return false;
        return true;
    }

    function createToken(address _token, address _proposer, uint _value, uint _endBlockNumber, string calldata _subject, string calldata _content) external returns (address) {
        if(tokens[_token] != address(0)) {
            require(_check(tokens[_token]) == true, 'DemaxBallotFactory: WAIT_PENDING_BALLOT');
        }
        address ballotAddr = _create(_proposer, _value, _endBlockNumber, _subject, _content);
        tokens[_token] = ballotAddr;
        return ballotAddr;
    }

    function createKey(bytes32 _key, address _proposer, uint _value, uint _endBlockNumber, string calldata _subject, string calldata _content) external returns (address) {
        if(keys[_key] != address(0)) {
            require(_check(keys[_key]) == true, 'DemaxBallotFactory: WAIT_PENDING_BALLOT');
        }
        address ballotAddr = _create(_proposer, _value, _endBlockNumber, _subject, _content);
        keys[_key] = ballotAddr;
        return ballotAddr;
    }
}
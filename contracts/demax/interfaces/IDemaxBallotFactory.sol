pragma solidity >=0.5.0;

interface IDemaxBallotFactory {
    function createToken(address _token, address _proposer, uint _value, uint _endBlockNumber, string calldata _subject, string calldata _content) external returns (address);
    function createKey(bytes32 _key, address _proposer, uint _value, uint _endBlockNumber, string calldata _subject, string calldata _content) external returns (address);
}

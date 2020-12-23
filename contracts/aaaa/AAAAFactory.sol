// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

import "./AAAA.sol";
import "./modules/Configable.sol";

interface IAAAAPool {
    function init(address supplyToken,  address collateralToken) external;
    function setupConfig(address config) external;
}

interface IAAAABallot {
    function initialize(address creator, address pool, bytes32 name, uint value, uint reward, string calldata subject, string calldata content) external;
    function setupConfig(address config) external;
}

contract AAAAFactory is Configable{

    event PoolCreated(address indexed lendToken, address indexed collateralToken, address indexed pool);
    event BallotCreated(address indexed creator, address indexed pool, address indexed ballot, bytes32 name, uint value);

    
    address[] public allPools;
    mapping(address => bool) public isPool;
    mapping (address => mapping (address => address)) public getPool;
    
    address[] public allBallots;
    bytes32 ballotByteCodeHash;

    function createPool(address _lendToken, address _collateralToken) onlyDeveloper external returns (address pool) {
        require(getPool[_lendToken][_collateralToken] == address(0), "ALREADY CREATED");
        
        bytes32 salt = keccak256(abi.encodePacked(_lendToken, _collateralToken));
        bytes memory bytecode = type(AAAAPool).creationCode;
        assembly {
            pool := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        getPool[_lendToken][_collateralToken] = pool;
            
        allPools.push(pool);
        isPool[pool] = true;
        IConfig(config).initPoolParams(pool);
        IAAAAPool(pool).setupConfig(config);
        IAAAAPool(pool).init(_lendToken, _collateralToken);
        
        emit PoolCreated(_lendToken, _collateralToken, pool);
        return pool;
    }

    function countPools() external view returns(uint) {
        return allPools.length;
    }
    
    function createBallot(
        address _creator, 
        address _pool, 
        bytes32 _name, 
        uint _value, 
        uint _reward, 
        string calldata _subject, 
        string calldata _content, 
        bytes calldata _bytecode) onlyGovernor external returns (address ballot) 
    {
        bytes32 salt = keccak256(abi.encodePacked(_creator, _value, _subject, block.number));
        bytes memory bytecode = _bytecode;
        require(keccak256(bytecode) == ballotByteCodeHash, "INVALID BYTECODE.");
        
        assembly {
            ballot := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        allBallots.push(ballot);
        IAAAABallot(ballot).setupConfig(config);
        IAAAABallot(ballot).initialize(_creator, _pool, _name, _value, _reward, _subject, _content);
        
        emit BallotCreated(_creator, _pool, ballot, _name, _value);
        return ballot;
    }
    
    function countBallots() external view returns (uint){
        return allBallots.length;
    }

    function changeBallotByteHash(bytes32 _hash) onlyDeveloper external {
        ballotByteCodeHash = _hash;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

import './SLPStrategy.sol';
import './modules/Configable.sol';

interface ISLPStrategy {
    function initialize(address _interestToken, address _collateralToken, address _poolAddress, address _sushiMasterChef, uint _lpPoolpid) external;
}

interface ISushiMasterChef {
    function sushi() external view returns(address);
}

interface IAAAAPool {
    function collateralToken() external view returns(address);
}

contract SLPStrategyFactory is Configable {
    address public masterchef;
    address[] public strategies;

    event StrategyCreated(address indexed _strategy, address indexed _collateralToken, address indexed _poolAddress, uint _lpPoolpid);

    constructor() public {
        owner = msg.sender;
    }

    function initialize(address _masterchef) onlyOwner public {
        masterchef = _masterchef;
    }

    function createStrategy(address _collateralToken, address _poolAddress, uint _lpPoolpid) onlyDeveloper external returns (address _strategy) {
        require(IAAAAPool(_poolAddress).collateralToken() == _collateralToken, 'Not found collateralToken in Pool');
        (address cToken, , ,) = IMasterChef(masterchef).poolInfo(_lpPoolpid);
        require(cToken == _collateralToken, 'Not found collateralToken in Masterchef');
        
        bytes memory bytecode = type(SLPStrategy).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_collateralToken, _poolAddress, _lpPoolpid, block.number));
        assembly {
            _strategy := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        address _interestToken = ISushiMasterChef(masterchef).sushi();
        ISLPStrategy(_strategy).initialize(_interestToken, _collateralToken, _poolAddress, masterchef, _lpPoolpid);
        emit StrategyCreated(_strategy, _collateralToken, _poolAddress, _lpPoolpid);
        strategies.push(_strategy);
        return _strategy;
    }

    function countStrategy() external view returns(uint) {
        return strategies.length;
    }

}

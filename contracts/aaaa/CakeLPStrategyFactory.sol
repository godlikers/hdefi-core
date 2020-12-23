// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

import './CakeLPStrategy.sol';
import './modules/Configable.sol';

interface ICakeLPStrategy {
    function initialize(address _interestToken, address _collateralToken, address _poolAddress, address _cakeMasterChef, uint _lpPoolpid) external;
}

interface ICakeMasterChef {
    function cake() external view returns(address);
}

interface IAAAAPool {
    function collateralToken() external view returns(address);
}

contract CakeLPStrategyFactory is Configable {
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
        
        bytes memory bytecode = type(CakeLPStrategy).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_collateralToken, _poolAddress, _lpPoolpid, block.number));
        assembly {
            _strategy := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        address _interestToken = ICakeMasterChef(masterchef).cake();
        ICakeLPStrategy(_strategy).initialize(_interestToken, _collateralToken, _poolAddress, masterchef, _lpPoolpid);
        emit StrategyCreated(_strategy, _collateralToken, _poolAddress, _lpPoolpid);
        strategies.push(_strategy);
        return _strategy;
    }

    function countStrategy() external view returns(uint) {
        return strategies.length;
    }

}

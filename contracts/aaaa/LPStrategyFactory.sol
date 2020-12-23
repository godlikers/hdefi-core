// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

import './LPStrategy.sol';
import './modules/Configable.sol';

interface IAAAAPool {
    function collateralToken() external view returns(address);
}

contract LPStrategyFactory is Configable {
    address public dgas;
    address public demaxPool;
    address[] public strategies;

    event StrategyCreated(address indexed _strategy, address indexed _collateralToken, address indexed _poolAddress);

    constructor() public {
        owner = msg.sender;
    }

    function initialize(address _demaxPool) onlyOwner public {
        demaxPool = _demaxPool;
        dgas = IDemaxPool(_demaxPool).DGAS();
    }

    function createStrategy(address _collateralToken, address _poolAddress, uint) onlyDeveloper external returns (address _strategy) {
        require(IAAAAPool(_poolAddress).collateralToken() == _collateralToken, 'Not found collateralToken in Pool');
        bytes memory bytecode = type(LPStrategy).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_collateralToken, _poolAddress, block.number));
        assembly {
            _strategy := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        LPStrategy(_strategy).initialize(dgas, _collateralToken, _poolAddress, demaxPool, _collateralToken);
        emit StrategyCreated(_strategy, _collateralToken, _poolAddress);
        strategies.push(_strategy);
        return _strategy;
    }

    function countStrategy() external view returns(uint) {
        return strategies.length;
    }

}

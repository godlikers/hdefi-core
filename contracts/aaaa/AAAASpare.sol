pragma solidity >=0.5.16;
import "./libraries/TransferHelper.sol";

contract AAAASpare {
    address public owner;
    mapping (address => bool) pools;
    
    constructor() public {
        owner = msg.sender;
    }
    
    function setValidPool(address _pool, bool _valid) external {
        require(msg.sender == owner, "FORBIDDEN");
        pools[_pool] = _valid;
    }
    
    function take(address _token, uint _amount) external {
        require(pools[msg.sender] = true, "FORBIDDEN");
        TransferHelper.safeTransfer(_token, msg.sender, _amount);
    }
    
    function withdraw(address _token, address _to, uint _amount) external {
        require(msg.sender == owner, "FORBIDDEN");
        TransferHelper.safeTransfer(_token, _to, _amount);
    }
}

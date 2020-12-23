// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;
import "./libraries/TransferHelper.sol";
import "./libraries/SafeMath.sol";
import "./modules/BaseShareField.sol";

interface ICollateralStrategy {
    function invest(address user, uint amount) external; 
    function withdraw(address user, uint amount) external;
    function liquidation(address user) external;
    function claim(address user, uint amount, uint total) external;
    function exit(uint amount) external;
    function migrate(address old) external;
    function query() external view returns (uint);
    function mint() external;

    function interestToken() external returns (address);
    function collateralToken() external returns (address);
}

interface IDemaxPool {
    function queryReward(address _pair, address _user) external view returns(uint);
    function claimReward(address _pair, address _rewardToken) external;
    function DGAS() external view returns(address);
}

interface IDemaxPair {
    function mintReward() external returns (uint256);
    function queryReward() external view returns (uint256, uint256);
}

contract LPStrategy is ICollateralStrategy, BaseShareField
{
    event Mint(address indexed user, uint amount);
    using SafeMath for uint;

    address override public interestToken;
    address override public collateralToken;

    address public poolAddress;
    address public masterChef;
    address public old;
    address public demaxPool;
    address public pair;

    address public factory;

    constructor() public {
        factory = msg.sender;
    }

    function initialize(address _interestToken, address _collateralToken, address _poolAddress, address _demaxPool, address _pair) public
    {
        require(msg.sender == factory, 'STRATEGY FORBIDDEN');
        interestToken = _interestToken;
        collateralToken = _collateralToken;
        poolAddress = _poolAddress;
        demaxPool = _demaxPool;
        pair = _pair;
        _setShareToken(_interestToken);
    }

    function migrate(address _old) external override 
    {
        require(msg.sender == poolAddress, "INVALID CALLER");
        if(_old != address(0)) {
            totalProductivity = BaseShareField(_old).totalProductivity();
            old = _old;
        }
    }

    function invest(address user, uint amount) external override
    {
        _sync(user);

        require(msg.sender == poolAddress, "INVALID CALLER");
        TransferHelper.safeTransferFrom(collateralToken, msg.sender, address(this), amount);
        _increaseProductivity(user, amount);
    }

    function withdraw(address user, uint amount) external override
    {
        _sync(user);

        require(msg.sender == poolAddress, "INVALID CALLER");

        _takeInterest();
        TransferHelper.safeTransfer(collateralToken, msg.sender, amount);
        _decreaseProductivity(user, amount);
    }

    function liquidation(address user) external override {
        _sync(user);
        _sync(msg.sender);

        require(msg.sender == poolAddress, "INVALID CALLER");
        uint amount = users[user].amount;
        _decreaseProductivity(user, amount);

        uint reward = users[user].rewardEarn;
        users[msg.sender].rewardEarn = users[msg.sender].rewardEarn.add(reward);
        users[user].rewardEarn = 0;
        _increaseProductivity(msg.sender, amount);
    }

    function claim(address user, uint amount, uint total) external override {
        _sync(msg.sender);

        require(msg.sender == poolAddress, "INVALID CALLER");
        _takeInterest();

        TransferHelper.safeTransfer(collateralToken, msg.sender, amount);
        _decreaseProductivity(msg.sender, amount);
    
        uint claimAmount = users[msg.sender].rewardEarn.mul(amount).div(total);
        users[user].rewardEarn = users[user].rewardEarn.add(claimAmount);
        users[msg.sender].rewardEarn = users[msg.sender].rewardEarn.sub(claimAmount);
    }

    function exit(uint amount) external override {
        require(msg.sender == poolAddress, "INVALID CALLER");
        TransferHelper.safeTransfer(collateralToken, msg.sender, amount);
    }

    function _takeInterest() internal {
        if(IDemaxPool(demaxPool).queryReward(pair, address(this)) > 0) {
            IDemaxPool(demaxPool).claimReward(pair, interestToken);
        }
        (uint pairAmount, ) = IDemaxPair(pair).queryReward();
        if(pairAmount > 0) {
            IDemaxPair(pair).mintReward();
        }
    }

    function _sync(address user) internal 
    {
        if(old != address(0) && users[user].initialize == false) {
            (uint amount, ) = BaseShareField(old).getProductivity(user);
            users[user].amount = amount;
            users[user].initialize = true;
        } 
    }

    function _currentReward() internal override view returns (uint) {
        uint poolAmount = IDemaxPool(demaxPool).queryReward(pair, address(this));
        (uint pairAmount, ) = IDemaxPair(pair).queryReward();

        return mintedShare.add(IERC20(shareToken).balanceOf(address(this))).add(poolAmount).add(pairAmount).sub(totalShare);
    }

    function query() external override view returns (uint){
        return _takeWithAddress(msg.sender);
    }

    function mint() external override {
        _sync(msg.sender);
        
        _takeInterest();
        uint amount = _mint(msg.sender);
        emit Mint(msg.sender, amount);
    }
}
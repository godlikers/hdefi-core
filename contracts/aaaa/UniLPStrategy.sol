// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;
import "./interface/IERC20.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/SafeMath.sol";
import "./modules/Configable.sol";

interface ICollateralStrategy {
    function invest(uint amount) external;
    function withdraw(uint amount) external returns(uint);
    function interestToken() external returns (address);
    function collateralToken() external returns (address);
}

interface IUniswapStakingReward {
    // Views
    function lastTimeRewardApplicable() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function getRewardForDuration() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    // Mutative
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function exit() external;
}

contract UniLPStrategy is ICollateralStrategy
{
    using SafeMath for uint;

    address override public interestToken;
    address override public collateralToken;

    address public poolAddress;
    address public uniswapPoolAddress;

    constructor(address _interestToken, address _collateralToken, address _poolAddress, address _uniswapPoolAddress) public
    {
        interestToken = _interestToken;
        collateralToken = _collateralToken;
        poolAddress = _poolAddress;
        uniswapPoolAddress = _uniswapPoolAddress;
    }

    function invest(uint amount) external override
    {
        require(msg.sender == poolAddress, "INVALID CALLER");
        TransferHelper.safeTransferFrom(collateralToken, msg.sender, address(this), amount);
        IERC20(collateralToken).approve(uniswapPoolAddress, amount);
        IUniswapStakingReward(uniswapPoolAddress).stake(amount);
    }

    function withdraw(uint amount) external override returns(uint interests)
    {
        require(msg.sender == poolAddress, "INVALID CALLER");
        IUniswapStakingReward(uniswapPoolAddress).withdraw(amount);
        IUniswapStakingReward(uniswapPoolAddress).getReward();
        interests = IERC20(interestToken).balanceOf(address(this));
        TransferHelper.safeTransfer(collateralToken, msg.sender, amount);
        if(interests > 0) TransferHelper.safeTransfer(interestToken, msg.sender, interests);
    }
}
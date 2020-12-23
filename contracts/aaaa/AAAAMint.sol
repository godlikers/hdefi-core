// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;
import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";
import "./modules/Configable.sol";
import "./modules/ConfigNames.sol";

contract AAAAMint is Configable {
    using SafeMath for uint;

    uint public mintCumulation;
    uint public amountPerBlock;
    
    uint public lastRewardBlock;
    uint public totalProductivity;
    uint public totalSupply;
    uint public accAmountPerShare;
    uint public maxSupply;

    struct UserInfo {
        uint amount;     // How many LP tokens the user has provided.
        uint rewardDebt; // Reward debt. 
        uint rewardEarn; // Reward earn and not minted
    }

    mapping(address => UserInfo) public users;
    
    event InterestsPerBlockChanged (uint oldValue, uint newValue);
    event ProductivityIncreased (address indexed user, uint value);
    event ProductivityDecreased (address indexed user, uint value);
    event Mint(address indexed user, uint userAmount, uint teamAmount, uint rewardAmount, uint spareAmount);

    function addMintAmount(uint _amount) external virtual {
        TransferHelper.safeTransferFrom(IConfig(config).token(), msg.sender, address(this), _amount);
        maxSupply = maxSupply.add(_amount);
    }
 
    // External function call
    // This function adjust how many token will be produced by each block, eg:
    // changeAmountPerBlock(100)
    // will set the produce rate to 100/block.
    function sync() public virtual returns (bool) {
        uint value = IConfig(config).getValue(ConfigNames.MINT_AMOUNT_PER_BLOCK);
        uint old = amountPerBlock;
        require(value != old, 'AMOUNT_PER_BLOCK_NO_CHANGE');
        require(maxSupply > totalSupply, 'NO_BALANCE_TO_MINT');
        
        _update();
        amountPerBlock = value;

        emit InterestsPerBlockChanged(old, value);
        return true;
    }

    // Update reward variables of the given pool to be up-to-date.
    function _update() internal virtual {
        if (block.number <= lastRewardBlock) {
            return;
        }

        if (totalProductivity == 0) {
            lastRewardBlock = block.number;
            return;
        }
        
        uint256 reward = _currentReward();
        if(reward == 0) {
            amountPerBlock = 0;
        } else {
            totalSupply = totalSupply.add(reward);

            accAmountPerShare = accAmountPerShare.add(reward.mul(1e12).div(totalProductivity));
            lastRewardBlock = block.number;
        }
    }
    
    function _currentReward() internal virtual view returns (uint){
        uint256 multiplier = block.number.sub(lastRewardBlock);
        uint reward = multiplier.mul(amountPerBlock);
        if(totalSupply.add(reward) > maxSupply) {
            reward = maxSupply.sub(totalSupply);
        }
        
        return reward;
    }
    
    // Audit user's reward to be up-to-date
    function _audit(address user) internal virtual {
        UserInfo storage userInfo = users[user];
        if (userInfo.amount > 0) {
            uint pending = userInfo.amount.mul(accAmountPerShare).div(1e12).sub(userInfo.rewardDebt);
            userInfo.rewardEarn = userInfo.rewardEarn.add(pending);
            mintCumulation = mintCumulation.add(pending);
            userInfo.rewardDebt = userInfo.amount.mul(accAmountPerShare).div(1e12);
        }
    }

    // External function call
    // This function increase user's productivity and updates the global productivity.
    // the users' actual share percentage will calculated by:
    // Formula:     user_productivity / global_productivity
    function increaseProductivity(address user, uint value) external virtual onlyPlatform returns (bool) {
        require(value > 0, 'PRODUCTIVITY_VALUE_MUST_BE_GREATER_THAN_ZERO');

        UserInfo storage userInfo = users[user];
        _update();
        _audit(user);

        totalProductivity = totalProductivity.add(value);

        userInfo.amount = userInfo.amount.add(value);
        userInfo.rewardDebt = userInfo.amount.mul(accAmountPerShare).div(1e12);
        emit ProductivityIncreased(user, value);
        return true;
    }

    // External function call 
    // This function will decreases user's productivity by value, and updates the global productivity
    // it will record which block this is happenning and accumulates the area of (productivity * time)
    function decreaseProductivity(address user, uint value) external virtual onlyPlatform returns (bool) {
        UserInfo storage userInfo = users[user];
        require(value > 0 && userInfo.amount >= value, "INSUFFICIENT_PRODUCTIVITY");
        _update();
        _audit(user);
        
        userInfo.amount = userInfo.amount.sub(value);
        userInfo.rewardDebt = userInfo.amount.mul(accAmountPerShare).div(1e12);
        totalProductivity = totalProductivity.sub(value);

        emit ProductivityDecreased(user, value);
        return true;
    }
    
    function takeWithAddress(address user) public view returns (uint) {
        UserInfo storage userInfo = users[user];
        uint _accAmountPerShare = accAmountPerShare;
        // uint256 lpSupply = totalProductivity;
        if (totalProductivity != 0) {
            uint reward = _currentReward();
            _accAmountPerShare = _accAmountPerShare.add(reward.mul(1e12).div(totalProductivity));
        }
        uint amount = userInfo.amount.mul(_accAmountPerShare).div(1e12).sub(userInfo.rewardDebt).add(userInfo.rewardEarn);
        return amount.mul(IConfig(config).getValue(ConfigNames.AAAA_USER_MINT)).div(10000);
    }

    function take() external virtual view returns (uint) {
        return takeWithAddress(msg.sender);
    }

    // Returns how much a user could earn plus the giving block number.
    function takeWithBlock() external virtual view returns (uint, uint) {
        uint earn = takeWithAddress(msg.sender);
        return (earn, block.number);
    }


    // External function call
    // When user calls this function, it will calculate how many token will mint to user from his productivity * time
    // Also it calculates global token supply from last time the user mint to this time.
    function mint() external virtual returns (uint) {
        _update();
        _audit(msg.sender);
        require(users[msg.sender].rewardEarn > 0, "NOTHING_TO_MINT");
        uint amount = users[msg.sender].rewardEarn;
        _mintDistribution(msg.sender, amount);
        users[msg.sender].rewardEarn = 0;
        return amount;
    }

    // Returns how many productivity a user has and global has.
    function getProductivity(address user) external virtual view returns (uint, uint) {
        return (users[user].amount, totalProductivity);
    }

    // Returns the current gorss product rate.
    function interestsPerBlock() external virtual view returns (uint) {
        return accAmountPerShare;
    }
    
    function _mintDistribution(address user, uint amount) internal {
        uint userAmount = amount.mul(IConfig(config).getValue(ConfigNames.AAAA_USER_MINT)).div(10000);
        uint remainAmount = amount.sub(userAmount);
        uint teamAmount = remainAmount.mul(IConfig(config).getValue(ConfigNames.AAAA_TEAM_MINT)).div(10000);
        if(teamAmount > 0) {
            TransferHelper.safeTransfer(IConfig(config).token(), IConfig(config).wallets(ConfigNames.TEAM), teamAmount);
        }
        
        remainAmount = remainAmount.sub(teamAmount);
        uint rewardAmount = remainAmount.mul(IConfig(config).getValue(ConfigNames.AAAA_REWAED_MINT)).div(10000);
        if(rewardAmount > 0) {
            TransferHelper.safeTransfer(IConfig(config).token(), IConfig(config).wallets(ConfigNames.REWARD), rewardAmount);
        }  

        uint spareAmount = remainAmount.sub(rewardAmount);
        if(spareAmount > 0) {
            TransferHelper.safeTransfer(IConfig(config).token(), IConfig(config).wallets(ConfigNames.SPARE), spareAmount);
        }
        
        if(userAmount > 0) {
           TransferHelper.safeTransfer(IConfig(config).token(), user, userAmount); 
        }
        emit Mint(user, userAmount, teamAmount, rewardAmount, spareAmount);
    }
}
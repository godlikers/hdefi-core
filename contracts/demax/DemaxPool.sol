pragma solidity >= 0.5.1;
import './modules/Ownable.sol';
import './libraries/TransferHelper.sol';
import './interfaces/IDgas.sol';
import './interfaces/IDemaxPair.sol';
import './interfaces/IDemaxFactory.sol';
import './interfaces/IDemaxGovernance.sol';
import './libraries/SafeMath.sol';
import './libraries/ConfigNames.sol';
import './interfaces/IDemaxConfig.sol';

interface IDemaxPlatform {
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) ;
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function existPair(address tokenA, address tokenB) external view returns (bool);
}

contract DemaxPool is Ownable {
    using SafeMath for uint;
    address public DGAS;
    address public FACTORY;
    address public PLATFORM;
    address public WETH;
    address public CONFIG;
    address public GOVERNANCE;
    uint public totalReward;
    
    struct UserInfo {
        uint amount;
        uint rewardDebt; // Reward debt. 
        uint rewardEarn; // Reward earn and not minted
    }

    struct FeeCumulation {
        uint total;
        uint liquidity;
        uint governance;
        uint burn;
    }

    FeeCumulation public feeCumulation;
    
    event ClaimReward(address indexed user, address indexed pair, address indexed rewardToken, uint amountDGAS);
    event AddReward(address indexed pair, uint amount);

    mapping(address => mapping (address => UserInfo)) public users;
    
    mapping (address => uint) public pairAmountPerShare;
    mapping (address => uint) public pairReward;
    
    function initialize(address _DGAS, address _WETH, address _FACTORY, address _PLATFORM, address _CONFIG, address _GOVERNANCE) external onlyOwner {
        DGAS = _DGAS;
        WETH = _WETH;
        FACTORY = _FACTORY;
        PLATFORM = _PLATFORM;
        CONFIG = _CONFIG;
        GOVERNANCE = _GOVERNANCE;
    }

    function upgradeFee(address _oldPool) external onlyOwner {
        (feeCumulation.total, feeCumulation.liquidity, feeCumulation.governance, feeCumulation.burn) = DemaxPool(_oldPool).feeCumulation();
    }
    
    function upgrade(address _newPool, address[] calldata _pairs) external onlyOwner {
        IDgas(DGAS).approve(_newPool, totalReward);
        for(uint i = 0;i < _pairs.length;i++) {
            if(pairReward[_pairs[i]] > 0) {
                DemaxPool(_newPool).addReward(_pairs[i], pairReward[_pairs[i]]);
                totalReward = totalReward.sub(pairReward[_pairs[i]]);
                pairReward[_pairs[i]] = 0;
            }
        }
    }
    
    function addRewardFromPlatform(address _pair, uint _amount) external {
        require(msg.sender == PLATFORM, "DEMAX POOL: FORBIDDEN");
        uint balanceOf = IDgas(DGAS).balanceOf(address(this));
        require(balanceOf.sub(totalReward) >= _amount, 'DEMAX POOL: ADD_REWARD_EXCEED');
        
        uint rewardAmount = IDemaxConfig(CONFIG).getConfigValue(ConfigNames.FEE_LP_REWARD_PERCENT).mul(_amount).div(10000);
        _addReward(_pair, rewardAmount);
        
        uint remainAmount = _amount.sub(rewardAmount);
        uint governanceAmount = IDemaxConfig(CONFIG).getConfigValue(ConfigNames.FEE_GOVERNANCE_REWARD_PERCENT).mul(remainAmount).div(10000);
        if(governanceAmount > 0) {
            TransferHelper.safeTransfer(DGAS, GOVERNANCE, governanceAmount);
            IDemaxGovernance(GOVERNANCE).addReward(governanceAmount);
        }
        uint burnAmount = remainAmount.sub(governanceAmount);
        if(burnAmount > 0) {
            TransferHelper.safeTransfer(DGAS, address(0), burnAmount);
        }

        feeCumulation.total = feeCumulation.total.add(_amount);
        feeCumulation.liquidity = feeCumulation.liquidity.add(rewardAmount);
        feeCumulation.governance = feeCumulation.governance.add(governanceAmount);
        feeCumulation.burn = feeCumulation.burn.add(burnAmount);
        emit AddReward(_pair, rewardAmount);
    }
    
    function addReward(address _pair, uint _amount) external {
        TransferHelper.safeTransferFrom(DGAS, msg.sender, address(this), _amount);
        
        require(IDemaxFactory(FACTORY).isPair(_pair), "DEMAX POOL: INVALID PAIR");
        _addReward(_pair, _amount);
        
        emit AddReward(_pair, _amount);
    }
    
    function increaseProdutivity(address _user, uint _amount) external {
        require(IDemaxFactory(FACTORY).isPair(msg.sender), "DEMAX POOL: FORBIDDEN");
        _auditUser(msg.sender, _user);
        users[_user][msg.sender].amount = users[_user][msg.sender].amount.add(_amount);
        _updateDebt(msg.sender, _user);
    }
    
    function decreaseProdutivity(address _user, uint _amount) external {
        require(IDemaxFactory(FACTORY).isPair(msg.sender), "DEMAX POOL: FORBIDDEN");
        _auditUser(msg.sender, _user);
        users[_user][msg.sender].amount = users[_user][msg.sender].amount.sub(_amount);
        _updateDebt(msg.sender, _user);
    }
    
    function _addReward(address _pair, uint _amount) internal {
        pairReward[_pair] = pairReward[_pair].add(_amount);
        uint totalProdutivity = IDemaxPair(_pair).totalSupply();
        if(totalProdutivity > 0) {
            pairAmountPerShare[_pair] = pairAmountPerShare[_pair].add(_amount.mul(1e12).div(totalProdutivity));
            totalReward = totalReward.add(_amount);
        }
    }
    
    function _auditUser(address _pair, address _user) internal {
        require(IDemaxFactory(FACTORY).isPair(_pair), "DEMAX POOL: INVALID PAIR");
        uint accAmountPerShare = pairAmountPerShare[_pair];
        UserInfo storage userInfo = users[_user][_pair];
        if(userInfo.amount > 0) {
            uint pending = userInfo.amount.mul(accAmountPerShare).div(1e12).sub(userInfo.rewardDebt);
            userInfo.rewardEarn = userInfo.rewardEarn.add(pending);
            userInfo.rewardDebt = userInfo.amount.mul(accAmountPerShare).div(1e12);
        }
    }
    
    function _updateDebt(address _pair, address _user) internal {
        UserInfo memory userInfo = users[_user][_pair];
        uint accAmountPerShare = pairAmountPerShare[_pair];
        users[_user][_pair].rewardDebt = userInfo.amount.mul(accAmountPerShare).div(1e12);
    }
    
    function claimReward(address _pair, address _rewardToken) external {
        _auditUser(_pair, msg.sender);
        UserInfo storage userInfo = users[msg.sender][_pair];
        
        uint amount = userInfo.rewardEarn;
        pairReward[_pair] = pairReward[_pair].sub(amount);
        totalReward = totalReward.sub(amount);
        require(amount > 0, "NOTHING TO MINT");
        
        if(_rewardToken == DGAS) {
            TransferHelper.safeTransfer(DGAS, msg.sender, amount);
        } else if(_rewardToken == WETH) {
            require(IDemaxFactory(FACTORY).getPair(WETH, DGAS) != address(0), "DEMAX POOL: INVALID PAIR");
            IDgas(DGAS).approve(PLATFORM, amount);
            address[] memory path = new address[](2);
            path[0] = DGAS;
            path[1] = WETH; 
            IDemaxPlatform(PLATFORM).swapExactTokensForETH(amount, 0, path, msg.sender, block.timestamp + 1);
        } else {
            require(IDemaxFactory(FACTORY).getPair(WETH, DGAS) != address(0), "DEMAX POOL: INVALID PAIR");
            IDgas(DGAS).approve(PLATFORM, amount);
            address[] memory path = new address[](2);
            path[0] = DGAS;
            path[1] = _rewardToken;
            IDemaxPlatform(PLATFORM).swapExactTokensForTokens(amount, 0, path, msg.sender, block.timestamp + 1);
        }
        
        userInfo.rewardEarn = 0;
        emit ClaimReward(msg.sender, _pair, _rewardToken, amount);
    }
    
    function queryReward(address _pair, address _user) external view returns(uint) {
        require(IDemaxFactory(FACTORY).isPair(_pair), "DEMAX POOL: INVALID PAIR");
        
        UserInfo memory userInfo = users[_user][_pair];
        uint balance = IDemaxPair(_pair).balanceOf(_user);
        return balance.mul(pairAmountPerShare[_pair]).div(1e12).add(userInfo.rewardEarn).sub(userInfo.rewardDebt);
    }
}
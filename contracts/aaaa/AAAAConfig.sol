// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;
import "./libraries/SafeMath.sol";
import './modules/ConfigNames.sol';

interface IERC20 {
    function balanceOf(address owner) external view returns (uint);
    function decimals() external view returns (uint8);
}

interface IAAAAPool {
    function collateralToken() external view returns(address);
}

contract AAAAConfig {
    using SafeMath for uint;
    using SafeMath for uint8;
    address public owner;
    address public factory;
    address public platform;
    address public developer;
    address public mint;
    address public token;
    address public share;
    address public base;
    address public governor;
    address public WETH;

    uint public lastPriceBlock;

    uint public DAY = 6400;
    uint public HOUR = 267;
    
    struct ConfigItem {
        uint min;
        uint max;
        uint span;
        uint value;
    }
    
    mapping (address => mapping (bytes32 => ConfigItem)) public poolParams;
    mapping (bytes32 => ConfigItem) public params;
    mapping (bytes32 => address) public wallets;
    mapping (address => uint) public prices;

    event PriceChange(address token, uint value);
    event ParameterChange(bytes32 key, uint value);
    event PoolParameterChange(address pool, bytes32 key, uint value);
    
    constructor() public {
        owner = msg.sender;
        developer = msg.sender;
        uint id;
        assembly {
            id := chainid()
        }
        if(id != 1) {
            DAY = 28800;
            HOUR = 1200;
        }
    }
    
    function initialize (address _platform, address _factory, address _mint, address _token, address _share, address _governor, address _base, address _WETH) external {
        require(msg.sender == owner || msg.sender == developer, "AAAA: Config FORBIDDEN");
        mint        = _mint;
        platform    = _platform;
        factory     = _factory;
        token       = _token;
        share       = _share;
        governor    = _governor;
        base        = _base;
        WETH        = _WETH;
    }

    function changeDeveloper(address _developer) external {
        require(msg.sender == owner || msg.sender == developer, "AAAA: Config FORBIDDEN");
        developer = _developer;
    }

    function setWallets(bytes32[] calldata _names, address[] calldata _wallets) external {
        require(msg.sender == owner || msg.sender == developer, "AAAA: ONLY DEVELOPER");
        require(_names.length == _wallets.length ,"AAAA: WALLETS LENGTH MISMATCH");
        for(uint i = 0; i < _names.length; i ++)
        {
            wallets[_names[i]] = _wallets[i];
        }
    }

    function initParameter() external {
        require(msg.sender == owner || msg.sender == developer, "AAAA: Config FORBIDDEN");
        _setParams(ConfigNames.PROPOSAL_VOTE_DURATION ,   1*DAY,  7*DAY , 1*DAY,  1*DAY);
        _setParams(ConfigNames.PROPOSAL_EXECUTE_DURATION, 1*HOUR, 48*HOUR, 1*HOUR, 1*HOUR);
        _setParams(ConfigNames.PROPOSAL_CREATE_COST, 0, 10000 * 1e18, 100 * 1e18, 0);
        _setParams(ConfigNames.STAKE_LOCK_TIME, 0, 7*DAY, 1*DAY, 0);
        _setParams(ConfigNames.MINT_AMOUNT_PER_BLOCK, 0, 10000 * 1e18, 1e17, 1e17);
        _setParams(ConfigNames.INTEREST_PLATFORM_SHARE, 0, 1e18, 1e17, 1e17);
        _setParams(ConfigNames.INTEREST_BUYBACK_SHARE, 10000, 10000, 0, 10000);
        _setParams(ConfigNames.CHANGE_PRICE_DURATION, 0, 500, 100, 0);
        _setParams(ConfigNames.CHANGE_PRICE_PERCENT, 1, 10000, 1, 2000);

        _setParams(ConfigNames.AAAA_USER_MINT, 0, 0, 0, 3000);
        _setParams(ConfigNames.AAAA_TEAM_MINT, 0, 0, 0, 7142);
        _setParams(ConfigNames.AAAA_REWAED_MINT, 0, 0, 0, 5000);
        _setParams(ConfigNames.DEPOSIT_ENABLE, 0, 0, 0, 1);
        _setParams(ConfigNames.WITHDRAW_ENABLE, 0, 0, 0, 1);
        _setParams(ConfigNames.BORROW_ENABLE, 0, 0, 0, 1);
        _setParams(ConfigNames.REPAY_ENABLE, 0, 0, 0, 1);
        _setParams(ConfigNames.LIQUIDATION_ENABLE, 0, 0, 0, 1);
        _setParams(ConfigNames.REINVEST_ENABLE, 0, 0, 0, 1);
    }

    function initPoolParams(address _pool) external {
        require(msg.sender == factory, "Config FORBIDDEN");
        _setPoolParams(_pool, ConfigNames.POOL_BASE_INTERESTS, 0, 1e18, 1e16, 2e17);
        _setPoolParams(_pool, ConfigNames.POOL_MARKET_FRENZY, 0, 1e18, 1e16, 2e17);
        _setPoolParams(_pool, ConfigNames.POOL_PLEDGE_RATE, 0, 1e18, 1e16, 6e17);
        _setPoolParams(_pool, ConfigNames.POOL_LIQUIDATION_RATE, 0, 1e18, 1e16, 9e17);
        _setPoolParams(_pool, ConfigNames.POOL_MINT_POWER, 0, 0, 0, 10000);
        _setPoolParams(_pool, ConfigNames.POOL_MINT_BORROW_PERCENT, 0, 10000, 1000, 5000);
    }

    function _setPoolValue(address _pool, bytes32 _key, uint _value) internal {
        poolParams[_pool][_key].value = _value;
        emit PoolParameterChange(_pool, _key, _value);
    }

    function _setParams(bytes32 _key, uint _min, uint _max, uint _span, uint _value) internal {
        params[_key] = ConfigItem(_min, _max, _span, _value);
        emit ParameterChange(_key, _value);
    }

    function _setPoolParams(address _pool, bytes32 _key, uint _min, uint _max, uint _span, uint _value) internal {
        poolParams[_pool][_key] = ConfigItem(_min, _max, _span, _value);
        emit PoolParameterChange(_pool, _key, _value);
    }

    function _setPrice(address _token, uint _value) internal {
        prices[_token] = _value;
        emit PriceChange(_token, _value);
    }

    function setTokenPrice(address[] calldata _tokens, uint[] calldata _prices) external {
        uint duration = params[ConfigNames.CHANGE_PRICE_DURATION].value;
        uint maxPercent = params[ConfigNames.CHANGE_PRICE_PERCENT].value;
        require(block.number >= lastPriceBlock.add(duration), "AAAA: Price Duration");
        require(msg.sender == wallets[bytes32("price")], "AAAA: Config FORBIDDEN");
        require(_tokens.length == _prices.length ,"AAAA: PRICES LENGTH MISMATCH");

        for(uint i = 0; i < _tokens.length; i++)
        {
            if(prices[_tokens[i]] == 0) {
                _setPrice(_tokens[i], _prices[i]);
            } else {
                uint currentPrice = prices[_tokens[i]];
                if(_prices[i] > currentPrice) {
                    uint maxPrice = currentPrice.add(currentPrice.mul(maxPercent).div(10000));
                    _setPrice(_tokens[i], _prices[i] > maxPrice ? maxPrice: _prices[i]);
                } else {
                    uint minPrice = currentPrice.sub(currentPrice.mul(maxPercent).div(10000));
                    _setPrice(_tokens[i], _prices[i] < minPrice ? minPrice: _prices[i]);
                }
            } 
        }

        lastPriceBlock = block.number;
    }
    
    function setValue(bytes32 _key, uint _value) external {
        require(msg.sender == owner || msg.sender == governor || msg.sender == platform || msg.sender == developer, "AAAA: ONLY DEVELOPER");
        params[_key].value = _value;
        emit ParameterChange(_key, _value);
    }
    
    function setPoolValue(address _pool, bytes32 _key, uint _value) external {
        require(msg.sender == owner || msg.sender == governor || msg.sender == platform || msg.sender == developer, "AAAA: FORBIDDEN");
        _setPoolValue(_pool, _key, _value);
    }
    
    function getValue(bytes32 _key) external view returns (uint){
        return params[_key].value;
    }
    
    function getPoolValue(address _pool, bytes32 _key) external view returns (uint) {
        return poolParams[_pool][_key].value;
    } 

    function setParams(bytes32 _key, uint _min, uint _max, uint _span, uint _value) external {
        require(msg.sender == owner || msg.sender == governor || msg.sender == platform || msg.sender == developer, "AAAA: FORBIDDEN");
        _setParams(_key, _min, _max, _span, _value);
    }

    function setPoolParams(address _pool, bytes32 _key, uint _min, uint _max, uint _span, uint _value) external {
        require(msg.sender == owner || msg.sender == governor || msg.sender == platform || msg.sender == developer, "AAAA: FORBIDDEN");
        _setPoolParams(_pool, _key, _min, _max, _span, _value);
    }

    function getParams(bytes32 _key) external view returns (uint, uint, uint, uint) {
        ConfigItem memory item = params[_key];
        return (item.min, item.max, item.span, item.value);
    }

    function getPoolParams(address _pool, bytes32 _key) external view returns (uint, uint, uint, uint) {
        ConfigItem memory item = poolParams[_pool][_key];
        return (item.min, item.max, item.span, item.value);
    }

    function convertTokenAmount(address _fromToken, address _toToken, uint _fromAmount) external view returns(uint toAmount) {
        uint fromPrice = prices[_fromToken];
        uint toPrice = prices[_toToken];
        uint8 fromDecimals = IERC20(_fromToken).decimals();
        uint8 toDecimals = IERC20(_toToken).decimals();
        toAmount = _fromAmount.mul(fromPrice).div(toPrice);
        if(fromDecimals > toDecimals) {
            toAmount = toAmount.div(10 ** (fromDecimals.sub(toDecimals)));
        } else if(toDecimals > fromDecimals) {
            toAmount = toAmount.mul(10 ** (toDecimals.sub(fromDecimals)));
        }
    }
}
// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

import "./modules/Configable.sol";
import "./modules/ConfigNames.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";

interface IAAAAMint {
    function increaseProductivity(address user, uint value) external returns (bool);
    function decreaseProductivity(address user, uint value) external returns (bool);
    function getProductivity(address user) external view returns (uint, uint);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}

interface IAAAAPool {
    function deposit(uint _amountDeposit, address _from) external;
    function withdraw(uint _amountWithdraw, address _from) external returns(uint, uint);
    function borrow(uint _amountCollateral, uint _repayAmount, uint _expectBorrow, address _from) external;
    function repay(uint _amountCollateral, address _from) external returns(uint, uint);
    function liquidation(address _user, address _from) external returns (uint);
    function reinvest(address _from) external returns(uint);

    function switchStrategy(address _collateralStrategy) external;
    function supplys(address user) external view returns(uint,uint,uint,uint,uint);
    function borrows(address user) external view returns(uint,uint,uint,uint,uint);
    function getTotalAmount() external view returns (uint);
    function supplyToken() external view returns (address);
    function interestPerBorrow() external view returns(uint);
    function interestPerSupply() external view returns(uint);
    function lastInterestUpdate() external view returns(uint);
    function getInterests() external view returns(uint);
    function totalBorrow() external view returns(uint);
    function remainSupply() external view returns(uint);
    function liquidationPerSupply() external view returns(uint);
    function totalLiquidationSupplyAmount() external view returns(uint);
    function totalLiquidation() external view returns(uint);
}

interface IAAAAFactory {
    function getPool(address _lendToken, address _collateralToken) external view returns (address);
    function countPools() external view returns(uint);
    function allPools(uint index) external view returns (address);
}

contract AAAAPlatform is Configable {

    using SafeMath for uint;
    
    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Locked');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    receive() external payable {
    }

    function deposit(address _lendToken, address _collateralToken, uint _amountDeposit) external lock {
        require(IConfig(config).getValue(ConfigNames.DEPOSIT_ENABLE) == 1, "NOT ENABLE NOW");
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");
        TransferHelper.safeTransferFrom(_lendToken, msg.sender, pool, _amountDeposit);
        IAAAAPool(pool).deposit(_amountDeposit, msg.sender);
        _updateProdutivity(pool);
    }
    
    function depositETH(address _lendToken, address _collateralToken) external payable lock {
        require(_lendToken == IConfig(config).WETH(), "INVALID WETH POOL");
        require(IConfig(config).getValue(ConfigNames.DEPOSIT_ENABLE) == 1, "NOT ENABLE NOW");
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");
        
        IWETH(IConfig(config).WETH()).deposit{value:msg.value}();
        TransferHelper.safeTransfer(_lendToken, pool, msg.value);
        IAAAAPool(pool).deposit(msg.value, msg.sender);
        _updateProdutivity(pool);
    }
    
    function withdraw(address _lendToken, address _collateralToken, uint _amountWithdraw) external lock {
        require(IConfig(config).getValue(ConfigNames.WITHDRAW_ENABLE) == 1, "NOT ENABLE NOW");
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");
        (uint withdrawSupplyAmount, uint withdrawLiquidationAmount) = IAAAAPool(pool).withdraw(_amountWithdraw, msg.sender);

        if(withdrawSupplyAmount > 0) _innerTransfer(_lendToken, msg.sender, withdrawSupplyAmount);
        if(withdrawLiquidationAmount > 0) _innerTransfer(_collateralToken, msg.sender, withdrawLiquidationAmount);

        _updateProdutivity(pool);
    }
    
    function borrow(address _lendToken, address _collateralToken, uint _amountCollateral, uint _expectBorrow) external lock {
        require(IConfig(config).getValue(ConfigNames.BORROW_ENABLE) == 1, "NOT ENABLE NOW");
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");
        if(_amountCollateral > 0) {
            TransferHelper.safeTransferFrom(_collateralToken, msg.sender, pool, _amountCollateral);
        }
        
        (, uint borrowAmountCollateral, , , ) = IAAAAPool(pool).borrows(msg.sender);
        uint repayAmount = getRepayAmount(_lendToken, _collateralToken, borrowAmountCollateral, msg.sender);
        IAAAAPool(pool).borrow(_amountCollateral, repayAmount, _expectBorrow, msg.sender);
        if(_expectBorrow > 0) _innerTransfer(_lendToken, msg.sender, _expectBorrow);
        _updateProdutivity(pool);
    }
    
    function borrowTokenWithETH(address _lendToken, address _collateralToken, uint _expectBorrow) external payable lock {
        require(_collateralToken == IConfig(config).WETH(), "INVALID WETH POOL");
        require(IConfig(config).getValue(ConfigNames.BORROW_ENABLE) == 1, "NOT ENABLE NOW");
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");
        
        if(msg.value > 0) {
            IWETH(IConfig(config).WETH()).deposit{value:msg.value}();
            TransferHelper.safeTransfer(_collateralToken, pool, msg.value);
        }
        
        (, uint borrowAmountCollateral, , , ) = IAAAAPool(pool).borrows(msg.sender);
        uint repayAmount = getRepayAmount(_lendToken, _collateralToken, borrowAmountCollateral, msg.sender);
        IAAAAPool(pool).borrow(msg.value, repayAmount, _expectBorrow, msg.sender);
        if(_expectBorrow > 0) _innerTransfer(_lendToken, msg.sender, _expectBorrow);
        _updateProdutivity(pool);
    }
    
    function repay(address _lendToken, address _collateralToken, uint _amountCollateral) external lock {
        require(IConfig(config).getValue(ConfigNames.REPAY_ENABLE) == 1, "NOT ENABLE NOW");
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");
        uint repayAmount = getRepayAmount(_lendToken, _collateralToken, _amountCollateral, msg.sender);
        
        if(repayAmount > 0) {
            TransferHelper.safeTransferFrom(_lendToken, msg.sender, pool, repayAmount);
        }
        
        IAAAAPool(pool).repay(_amountCollateral, msg.sender);
        _innerTransfer(_collateralToken, msg.sender, _amountCollateral);
        _updateProdutivity(pool);
    }

    function repayETH(address _lendToken, address _collateralToken, uint _amountCollateral) payable lock external {
        require(IConfig(config).getValue(ConfigNames.REPAY_ENABLE) == 1, "NOT ENABLE NOW");
        require(_lendToken == IConfig(config).WETH(), "INVALID WETH POOL");

        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");
        uint repayAmount = getRepayAmount(_lendToken, _collateralToken, _amountCollateral, msg.sender);

        require(repayAmount <= msg.value, "INVALID VALUE");

        if(repayAmount > 0) {
            IWETH(IConfig(config).WETH()).deposit{value:repayAmount}();
            TransferHelper.safeTransfer(_lendToken, pool, repayAmount);
        }
        
        IAAAAPool(pool).repay(_amountCollateral, msg.sender);
        _innerTransfer(_collateralToken, msg.sender, _amountCollateral);
        if(msg.value > repayAmount) TransferHelper.safeTransferETH(msg.sender, msg.value.sub(repayAmount));

        _updateProdutivity(pool);
    }
    
    function liquidation(address _lendToken, address _collateralToken, address _user) external lock {
        require(IConfig(config).getValue(ConfigNames.LIQUIDATION_ENABLE) == 1, "NOT ENABLE NOW");
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");
        IAAAAPool(pool).liquidation(_user, msg.sender);
        _updateProdutivity(pool);
    }

    function reinvest(address _lendToken, address _collateralToken) external lock {
        require(IConfig(config).getValue(ConfigNames.REINVEST_ENABLE) == 1, "NOT ENABLE NOW");
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");
        IAAAAPool(pool).reinvest(msg.sender);
        _updateProdutivity(pool);
    }
    
    function _innerTransfer(address _token, address _to, uint _amount) internal {
        if(_token == IConfig(config).WETH()) {
            IWETH(_token).withdraw(_amount);
            TransferHelper.safeTransferETH(_to, _amount);
        } else {
            TransferHelper.safeTransfer(_token, _to, _amount);
        }
    }

    function _updateProdutivity(address _pool) internal {
        uint power = IConfig(config).getPoolValue(_pool, ConfigNames.POOL_MINT_POWER);
        uint amount = IAAAAPool(_pool).getTotalAmount().mul(power).div(10000);
        (uint old, ) = IAAAAMint(IConfig(config).mint()).getProductivity(_pool);
        if(old > 0) {
            IAAAAMint(IConfig(config).mint()).decreaseProductivity(_pool, old);
        }
        
        address token = IAAAAPool(_pool).supplyToken();
        uint baseAmount = IConfig(config).convertTokenAmount(token, IConfig(config).base(), amount);
        if(baseAmount > 0) {
            IAAAAMint(IConfig(config).mint()).increaseProductivity(_pool, baseAmount);
        }
    }

    function getRepayAmount(address _lendToken, address _collateralToken, uint amountCollateral, address from) public view returns(uint repayAmount)
    {
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");

        (, uint borrowAmountCollateral, uint interestSettled, uint amountBorrow, uint borrowInterests) = IAAAAPool(pool).borrows(from);

        uint _interestPerBorrow = IAAAAPool(pool).interestPerBorrow().add(IAAAAPool(pool).getInterests().mul(block.number - IAAAAPool(pool).lastInterestUpdate()));
        uint _totalInterest = borrowInterests.add(_interestPerBorrow.mul(amountBorrow).div(1e18).sub(interestSettled));

        uint repayInterest = borrowAmountCollateral == 0 ? 0 : _totalInterest.mul(amountCollateral).div(borrowAmountCollateral);
        repayAmount = borrowAmountCollateral == 0 ? 0 : amountBorrow.mul(amountCollateral).div(borrowAmountCollateral).add(repayInterest);
    }

    function getMaximumBorrowAmount(address _lendToken, address _collateralToken, uint amountCollateral) external view returns(uint amountBorrow)
    {
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");

        uint pledgeAmount = IConfig(config).convertTokenAmount(_collateralToken, _lendToken, amountCollateral);
        uint pledgeRate = IConfig(config).getPoolValue(address(pool), ConfigNames.POOL_PLEDGE_RATE);

        amountBorrow = pledgeAmount.mul(pledgeRate).div(1e18);
    }

    function getLiquidationAmount(address _lendToken, address _collateralToken, address from) public view returns(uint liquidationAmount)
    {
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");

        (uint amountSupply, , uint liquidationSettled, , uint supplyLiquidation) = IAAAAPool(pool).supplys(from);

        liquidationAmount = supplyLiquidation.add(IAAAAPool(pool).liquidationPerSupply().mul(amountSupply).div(1e18).sub(liquidationSettled));
    }

    function getInterestAmount(address _lendToken, address _collateralToken, address from) public view returns(uint interestAmount)
    {
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");

        uint totalBorrow = IAAAAPool(pool).totalBorrow();
        uint totalSupply = totalBorrow + IAAAAPool(pool).remainSupply();
        (uint amountSupply, uint interestSettled, , uint interests, ) = IAAAAPool(pool).supplys(from);
        uint _interestPerSupply = IAAAAPool(pool).interestPerSupply().add(
            totalSupply == 0 ? 0 : IAAAAPool(pool).getInterests().mul(block.number - IAAAAPool(pool).lastInterestUpdate()).mul(totalBorrow).div(totalSupply));

        interestAmount = interests.add(_interestPerSupply.mul(amountSupply).div(1e18).sub(interestSettled));
    }

    function getWithdrawAmount(address _lendToken, address _collateralToken, address from) external view returns 
        (uint withdrawAmount, uint interestAmount, uint liquidationAmount)
    {
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");

        uint _totalInterest = getInterestAmount(_lendToken, _collateralToken, from);
        liquidationAmount = getLiquidationAmount(_lendToken, _collateralToken, from);

        uint platformShare = _totalInterest.mul(IConfig(config).getValue(ConfigNames.INTEREST_PLATFORM_SHARE)).div(1e18);
        interestAmount = _totalInterest.sub(platformShare);

        uint totalLiquidation = IAAAAPool(pool).totalLiquidation();

        uint withdrawLiquidationSupplyAmount = totalLiquidation == 0 ? 0 : 
            liquidationAmount.mul(IAAAAPool(pool).totalLiquidationSupplyAmount()).div(totalLiquidation);

        (uint amountSupply, , , , ) = IAAAAPool(pool).supplys(from);            

        if(withdrawLiquidationSupplyAmount > amountSupply.add(interestAmount))
            withdrawAmount = 0;
        else 
            withdrawAmount = amountSupply.add(interestAmount).sub(withdrawLiquidationSupplyAmount);
    }

    function switchStrategy(address _lendToken, address _collateralToken, address _collateralStrategy) external onlyDeveloper
    {
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");
        IAAAAPool(pool).switchStrategy(_collateralStrategy);
    }

    function updatePoolParameter(address _lendToken, address _collateralToken, bytes32 _key, uint _value) external onlyDeveloper
    {
        address pool = IAAAAFactory(IConfig(config).factory()).getPool(_lendToken, _collateralToken);
        require(pool != address(0), "POOL NOT EXIST");
        IConfig(config).setPoolValue(pool, _key, _value);
    }
}

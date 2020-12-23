// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;
import "./libraries/TransferHelper.sol";
import "./libraries/SafeMath.sol";
import "./modules/Configable.sol";
import "./modules/ConfigNames.sol";
import "./modules/BaseMintField.sol";

interface ICollateralStrategy {
    function invest(address user, uint amount) external; 
    function withdraw(address user, uint amount) external;
    function liquidation(address user) external;
    function claim(address user, uint amount, uint total) external;
    function exit(uint amount) external;
    function migrate(address old) external;
    function collateralToken() external returns (address);
}

interface IAAAAMint {
    function take() external view returns (uint);
    function mint() external returns (uint);
}

contract AAAAPool is Configable, BaseMintField
{
    using SafeMath for uint;

    address public factory;
    address public supplyToken;
    uint public supplyDecimal;
    address public collateralToken;
    uint public collateralDecimal;

    struct SupplyStruct {
        uint amountSupply;
        uint interestSettled;
        uint liquidationSettled;

        uint interests;
        uint liquidation;
    }

    struct BorrowStruct {
        uint index;
        uint amountCollateral;
        uint interestSettled;
        uint amountBorrow;
        uint interests;
    }

    struct LiquidationStruct {
        uint amountCollateral;
        uint liquidationAmount;
        uint timestamp;
    }

    address[] public borrowerList;
    uint public numberBorrowers;

    mapping(address => SupplyStruct) public supplys;
    mapping(address => BorrowStruct) public borrows;
    mapping(address => LiquidationStruct []) public liquidationHistory;
    mapping(address => uint) public liquidationHistoryLength;

    uint public interestPerSupply;
    uint public liquidationPerSupply;
    uint public interestPerBorrow;

    uint public totalLiquidation;
    uint public totalLiquidationSupplyAmount;

    uint public totalStake;
    uint public totalBorrow;
    uint public totalPledge;

    uint public remainSupply;

    uint public lastInterestUpdate;

    address public collateralStrategy;
    address[] public strategyList;
    uint strategyCount;

    event Deposit(address indexed _user, uint _amount, uint _collateralAmount);
    event Withdraw(address indexed _user, uint _supplyAmount, uint _collateralAmount, uint _interestAmount);
    event Borrow(address indexed _user, uint _supplyAmount, uint _collateralAmount);
    event Repay(address indexed _user, uint _supplyAmount, uint _collateralAmount, uint _interestAmount);
    event Liquidation(address indexed _liquidator, address indexed _user, uint _supplyAmount, uint _collateralAmount);
    event Reinvest(address indexed _user, uint _reinvestAmount);

    function switchStrategy(address _collateralStrategy) external onlyPlatform
    {

        if(collateralStrategy != address(0) && totalPledge > 0)
        {
            ICollateralStrategy(collateralStrategy).exit(totalPledge);
        }

        if(_collateralStrategy != address(0))
        {
            require(ICollateralStrategy(_collateralStrategy).collateralToken() == collateralToken && collateralStrategy != _collateralStrategy, "AAAA: INVALID STRATEGY");

            strategyCount++;
            strategyList.push(_collateralStrategy);

            if(totalPledge > 0) {
                TransferHelper.safeTransfer(collateralToken, _collateralStrategy, totalPledge);
            }
            ICollateralStrategy(_collateralStrategy).migrate(collateralStrategy);
        }

        collateralStrategy = _collateralStrategy;
    }

    constructor() public 
    {
        factory = msg.sender;
    }

    function init(address _supplyToken, address _collateralToken) external onlyFactory
    {
        supplyToken = _supplyToken;
        collateralToken = _collateralToken;

        lastInterestUpdate = block.number;
    }

    function updateInterests() internal
    {
        uint totalSupply = totalBorrow + remainSupply;
        uint interestPerBlock = getInterests();

        interestPerSupply = interestPerSupply.add(totalSupply == 0 ? 0 : interestPerBlock.mul(block.number - lastInterestUpdate).mul(totalBorrow).div(totalSupply));
        interestPerBorrow = interestPerBorrow.add(interestPerBlock.mul(block.number - lastInterestUpdate));
        lastInterestUpdate = block.number;
    }

    function getInterests() public view returns(uint interestPerBlock)
    {
        uint totalSupply = totalBorrow + remainSupply;
        uint baseInterests = IConfig(config).getPoolValue(address(this), ConfigNames.POOL_BASE_INTERESTS);
        uint marketFrenzy = IConfig(config).getPoolValue(address(this), ConfigNames.POOL_MARKET_FRENZY);
        uint aDay = IConfig(config).DAY();
        interestPerBlock = totalSupply == 0 ? 0 : baseInterests.add(totalBorrow.mul(marketFrenzy).div(totalSupply)).div(365 * aDay);
    }

    function updateLiquidation(uint _liquidation) internal
    {
        uint totalSupply = totalBorrow + remainSupply;
        liquidationPerSupply = liquidationPerSupply.add(totalSupply == 0 ? 0 : _liquidation.mul(1e18).div(totalSupply));
    }

    function deposit(uint amountDeposit, address from) public onlyPlatform
    {
        require(amountDeposit > 0, "AAAA: INVALID AMOUNT");
        uint amountIn = IERC20(supplyToken).balanceOf(address(this)).sub(remainSupply);
        require(amountIn >= amountDeposit, "AAAA: INVALID AMOUNT");

        updateInterests();

        uint addLiquidation = liquidationPerSupply.mul(supplys[from].amountSupply).div(1e18).sub(supplys[from].liquidationSettled);

        supplys[from].interests = supplys[from].interests.add(interestPerSupply.mul(supplys[from].amountSupply).div(1e18).sub(supplys[from].interestSettled));
        supplys[from].liquidation = supplys[from].liquidation.add(addLiquidation);

        supplys[from].amountSupply = supplys[from].amountSupply.add(amountDeposit);
        remainSupply = remainSupply.add(amountDeposit);
        
        totalStake = totalStake.add(amountDeposit);
        _mintToPool();
        _increaseLenderProductivity(from, amountDeposit);

        supplys[from].interestSettled = interestPerSupply.mul(supplys[from].amountSupply).div(1e18);
        supplys[from].liquidationSettled = liquidationPerSupply.mul(supplys[from].amountSupply).div(1e18);
        emit Deposit(from, amountDeposit, addLiquidation);
    }

    function reinvest(address from) public onlyPlatform returns(uint reinvestAmount)
    {
        updateInterests();

        uint addLiquidation = liquidationPerSupply.mul(supplys[from].amountSupply).div(1e18).sub(supplys[from].liquidationSettled);

        supplys[from].interests = supplys[from].interests.add(interestPerSupply.mul(supplys[from].amountSupply).div(1e18).sub(supplys[from].interestSettled));
        supplys[from].liquidation = supplys[from].liquidation.add(addLiquidation);

        reinvestAmount = supplys[from].interests;

        uint platformShare = reinvestAmount.mul(IConfig(config).getValue(ConfigNames.INTEREST_PLATFORM_SHARE)).div(1e18);
        reinvestAmount = reinvestAmount.sub(platformShare);

        supplys[from].amountSupply = supplys[from].amountSupply.add(reinvestAmount);
        totalStake = totalStake.add(reinvestAmount);
        supplys[from].interests = 0;

        supplys[from].interestSettled = supplys[from].amountSupply == 0 ? 0 : interestPerSupply.mul(supplys[from].amountSupply).div(1e18);
        supplys[from].liquidationSettled = supplys[from].amountSupply == 0 ? 0 : liquidationPerSupply.mul(supplys[from].amountSupply).div(1e18);

        distributePlatformShare(platformShare);
        _mintToPool();
        if(reinvestAmount > 0) {
           _increaseLenderProductivity(from, reinvestAmount); 
        }

        emit Reinvest(from, reinvestAmount);
    }

    function distributePlatformShare(uint platformShare) internal 
    {
        require(platformShare <= remainSupply, "AAAA: NOT ENOUGH PLATFORM SHARE");
        if(platformShare > 0) {
            uint buybackShare = IConfig(config).getValue(ConfigNames.INTEREST_BUYBACK_SHARE);
            uint buybackAmount = platformShare.mul(buybackShare).div(1e18);
            uint dividendAmount = platformShare.sub(buybackAmount);
            if(dividendAmount > 0) TransferHelper.safeTransfer(supplyToken, IConfig(config).share(), dividendAmount);
            if(buybackAmount > 0) TransferHelper.safeTransfer(supplyToken, IConfig(config).wallets(bytes32("team")), buybackAmount);
            remainSupply = remainSupply.sub(platformShare);
        }
    }

    function withdraw(uint amountWithdraw, address from) public onlyPlatform returns(uint withdrawSupplyAmount, uint withdrawLiquidation)
    {
        require(amountWithdraw > 0, "AAAA: INVALID AMOUNT");
        require(amountWithdraw <= supplys[from].amountSupply, "AAAA: NOT ENOUGH BALANCE");

        updateInterests();

        uint addLiquidation = liquidationPerSupply.mul(supplys[from].amountSupply).div(1e18).sub(supplys[from].liquidationSettled);

        supplys[from].interests = supplys[from].interests.add(interestPerSupply.mul(supplys[from].amountSupply).div(1e18).sub(supplys[from].interestSettled));
        supplys[from].liquidation = supplys[from].liquidation.add(addLiquidation);

        withdrawLiquidation = supplys[from].liquidation.mul(amountWithdraw).div(supplys[from].amountSupply);
        uint withdrawInterest = supplys[from].interests.mul(amountWithdraw).div(supplys[from].amountSupply);

        uint platformShare = withdrawInterest.mul(IConfig(config).getValue(ConfigNames.INTEREST_PLATFORM_SHARE)).div(1e18);
        uint userShare = withdrawInterest.sub(platformShare);

        distributePlatformShare(platformShare);

        uint withdrawLiquidationSupplyAmount = totalLiquidation == 0 ? 0 : withdrawLiquidation.mul(totalLiquidationSupplyAmount).div(totalLiquidation);
        
        if(withdrawLiquidationSupplyAmount < amountWithdraw.add(userShare))
            withdrawSupplyAmount = amountWithdraw.add(userShare).sub(withdrawLiquidationSupplyAmount);
        
        require(withdrawSupplyAmount <= remainSupply, "AAAA: NOT ENOUGH POOL BALANCE");
        require(withdrawLiquidation <= totalLiquidation, "AAAA: NOT ENOUGH LIQUIDATION");

        remainSupply = remainSupply.sub(withdrawSupplyAmount);
        totalLiquidation = totalLiquidation.sub(withdrawLiquidation);
        totalLiquidationSupplyAmount = totalLiquidationSupplyAmount.sub(withdrawLiquidationSupplyAmount);
        totalPledge = totalPledge.sub(withdrawLiquidation);

        supplys[from].interests = supplys[from].interests.sub(withdrawInterest);
        supplys[from].liquidation = supplys[from].liquidation.sub(withdrawLiquidation);
        supplys[from].amountSupply = supplys[from].amountSupply.sub(amountWithdraw);
        totalStake = totalStake.sub(amountWithdraw);

        supplys[from].interestSettled = supplys[from].amountSupply == 0 ? 0 : interestPerSupply.mul(supplys[from].amountSupply).div(1e18);
        supplys[from].liquidationSettled = supplys[from].amountSupply == 0 ? 0 : liquidationPerSupply.mul(supplys[from].amountSupply).div(1e18);

        _mintToPool();
        if(withdrawSupplyAmount > 0) {
            TransferHelper.safeTransfer(supplyToken, msg.sender, withdrawSupplyAmount);
        } 

        _decreaseLenderProductivity(from, amountWithdraw); 

        if(withdrawLiquidation > 0) {
            if(collateralStrategy != address(0))
            {
                ICollateralStrategy(collateralStrategy).claim(from, withdrawLiquidation, totalLiquidation.add(withdrawLiquidation));   
            }
            TransferHelper.safeTransfer(collateralToken, msg.sender, withdrawLiquidation);
        }
        
        emit Withdraw(from, withdrawSupplyAmount, withdrawLiquidation, withdrawInterest);
    }

    function borrow(uint amountCollateral, uint repayAmount, uint expectBorrow, address from) public onlyPlatform
    {
        uint amountIn = IERC20(collateralToken).balanceOf(address(this));
        if(collateralStrategy == address(0))
            amountIn = amountIn.sub(totalPledge);
            
        require(amountIn == amountCollateral, "AAAA: INVALID AMOUNT");

        // if(amountCollateral > 0) TransferHelper.safeTransferFrom(collateralToken, from, address(this), amountCollateral);

        updateInterests();
        
        uint pledgeRate = IConfig(config).getPoolValue(address(this), ConfigNames.POOL_PLEDGE_RATE);
        uint maxAmount = IConfig(config).convertTokenAmount(collateralToken, supplyToken, borrows[from].amountCollateral.add(amountCollateral));

        uint maximumBorrow = maxAmount.mul(pledgeRate).div(1e18);
        // uint repayAmount = getRepayAmount(borrows[from].amountCollateral, from);

        require(repayAmount + expectBorrow <= maximumBorrow, "AAAA: EXCEED MAX ALLOWED");
        require(expectBorrow <= remainSupply, "AAAA: INVALID BORROW");

        totalBorrow = totalBorrow.add(expectBorrow);
        totalPledge = totalPledge.add(amountCollateral);
        remainSupply = remainSupply.sub(expectBorrow);

        if(collateralStrategy != address(0) && amountCollateral > 0)
        {
            IERC20(ICollateralStrategy(collateralStrategy).collateralToken()).approve(collateralStrategy, amountCollateral);
            ICollateralStrategy(collateralStrategy).invest(from, amountCollateral); 
        }

        if(borrows[from].index == 0)
        {
            borrowerList.push(from);
            borrows[from].index = borrowerList.length;
            numberBorrowers ++;
        }

        borrows[from].interests = borrows[from].interests.add(interestPerBorrow.mul(borrows[from].amountBorrow).div(1e18).sub(borrows[from].interestSettled));
        borrows[from].amountCollateral = borrows[from].amountCollateral.add(amountCollateral);
        borrows[from].amountBorrow = borrows[from].amountBorrow.add(expectBorrow);
        borrows[from].interestSettled = interestPerBorrow.mul(borrows[from].amountBorrow).div(1e18);

        _mintToPool();
        if(expectBorrow > 0) {
            TransferHelper.safeTransfer(supplyToken, msg.sender, expectBorrow);
            _increaseBorrowerProductivity(from, expectBorrow);
        } 
        
        emit Borrow(from, expectBorrow, amountCollateral);
    }

    function repay(uint amountCollateral, address from) public onlyPlatform returns(uint repayAmount, uint repayInterest)
    {
        require(amountCollateral <= borrows[from].amountCollateral, "AAAA: NOT ENOUGH COLLATERAL");
        require(amountCollateral > 0, "AAAA: INVALID AMOUNT");

        uint amountIn = IERC20(supplyToken).balanceOf(address(this)).sub(remainSupply);

        updateInterests();

        borrows[from].interests = borrows[from].interests.add(interestPerBorrow.mul(borrows[from].amountBorrow).div(1e18).sub(borrows[from].interestSettled));

        repayAmount = borrows[from].amountBorrow.mul(amountCollateral).div(borrows[from].amountCollateral);
        repayInterest = borrows[from].interests.mul(amountCollateral).div(borrows[from].amountCollateral);

        totalPledge = totalPledge.sub(amountCollateral);
        totalBorrow = totalBorrow.sub(repayAmount);
        
        borrows[from].amountCollateral = borrows[from].amountCollateral.sub(amountCollateral);
        borrows[from].amountBorrow = borrows[from].amountBorrow.sub(repayAmount);
        borrows[from].interests = borrows[from].interests.sub(repayInterest);
        borrows[from].interestSettled = borrows[from].amountBorrow == 0 ? 0 : interestPerBorrow.mul(borrows[from].amountBorrow).div(1e18);

        remainSupply = remainSupply.add(repayAmount.add(repayInterest));

        if(collateralStrategy != address(0))
        {
            ICollateralStrategy(collateralStrategy).withdraw(from, amountCollateral);
        }
        TransferHelper.safeTransfer(collateralToken, msg.sender, amountCollateral);
        require(amountIn >= repayAmount.add(repayInterest), "AAAA: INVALID AMOUNT");
        // TransferHelper.safeTransferFrom(supplyToken, from, address(this), repayAmount.add(repayInterest));
        
        _mintToPool();
        if(repayAmount > 0) {
            _decreaseBorrowerProductivity(from, repayAmount);
        }

        emit Repay(from, repayAmount, amountCollateral, repayInterest);
    }

    function liquidation(address _user, address from) public onlyPlatform returns(uint borrowAmount)
    {
        require(supplys[from].amountSupply > 0, "AAAA: ONLY SUPPLIER");

        updateInterests();

        borrows[_user].interests = borrows[_user].interests.add(interestPerBorrow.mul(borrows[_user].amountBorrow).div(1e18).sub(borrows[_user].interestSettled));

        uint liquidationRate = IConfig(config).getPoolValue(address(this), ConfigNames.POOL_LIQUIDATION_RATE);
        
        // uint pledgePrice = IConfig(config).getPoolValue(address(this), ConfigNames.POOL_PRICE);
        // uint collateralValue = borrows[_user].amountCollateral.mul(pledgePrice).div(1e18);
        uint collateralValue = IConfig(config).convertTokenAmount(collateralToken, supplyToken, borrows[_user].amountCollateral);
        
        uint expectedRepay = borrows[_user].amountBorrow.add(borrows[_user].interests);

        require(expectedRepay >= collateralValue.mul(liquidationRate).div(1e18), 'AAAA: NOT LIQUIDABLE');

        updateLiquidation(borrows[_user].amountCollateral);

        totalLiquidation = totalLiquidation.add(borrows[_user].amountCollateral);
        totalLiquidationSupplyAmount = totalLiquidationSupplyAmount.add(expectedRepay);
        totalBorrow = totalBorrow.sub(borrows[_user].amountBorrow);

        borrowAmount = borrows[_user].amountBorrow;

        LiquidationStruct memory liq;
        liq.amountCollateral = borrows[_user].amountCollateral;
        liq.liquidationAmount = expectedRepay;
        liq.timestamp = block.timestamp;
        
        liquidationHistory[_user].push(liq);
        liquidationHistoryLength[_user] ++;
        if(collateralStrategy != address(0))
        {
            ICollateralStrategy(collateralStrategy).liquidation(_user);
        }
        
        emit Liquidation(from, _user, borrows[_user].amountBorrow, borrows[_user].amountCollateral);

        borrows[_user].amountCollateral = 0;
        borrows[_user].amountBorrow = 0;
        borrows[_user].interests = 0;
        borrows[_user].interestSettled = 0;
        
        _mintToPool();
        if(borrowAmount > 0) {
            _decreaseBorrowerProductivity(_user, borrowAmount);
        }
    }

    function getTotalAmount() external view returns (uint) {
        return totalStake.add(totalBorrow);
    }

    function _mintToPool() internal {
        if(IAAAAMint(IConfig(config).mint()).take() > 0) {
            IAAAAMint(IConfig(config).mint()).mint();
        }
    }

    function mint() external {
        _mintToPool();
        _mintLender();
        _mintBorrower();
    }

    function _currentReward() internal override view returns (uint) {
        uint remain = IAAAAMint(IConfig(config).mint()).take();
        return remain.add(mintedShare).add(IERC20(IConfig(config).token()).balanceOf(address(this))).sub(totalShare);
    }
}
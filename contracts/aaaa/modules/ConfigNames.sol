// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

library ConfigNames {
    //GOVERNANCE
    bytes32 public constant PROPOSAL_VOTE_DURATION = bytes32('PROPOSAL_VOTE_DURATION');
    bytes32 public constant PROPOSAL_EXECUTE_DURATION = bytes32('PROPOSAL_EXECUTE_DURATION');
    bytes32 public constant PROPOSAL_CREATE_COST = bytes32('PROPOSAL_CREATE_COST');
    bytes32 public constant STAKE_LOCK_TIME = bytes32('STAKE_LOCK_TIME');
    bytes32 public constant MINT_AMOUNT_PER_BLOCK =  bytes32('MINT_AMOUNT_PER_BLOCK');
    bytes32 public constant INTEREST_PLATFORM_SHARE =  bytes32('INTEREST_PLATFORM_SHARE');
    bytes32 public constant CHANGE_PRICE_DURATION =  bytes32('CHANGE_PRICE_DURATION');
    bytes32 public constant CHANGE_PRICE_PERCENT =  bytes32('CHANGE_PRICE_PERCENT');

    // POOL
    bytes32 public constant POOL_BASE_INTERESTS = bytes32('POOL_BASE_INTERESTS');
    bytes32 public constant POOL_MARKET_FRENZY = bytes32('POOL_MARKET_FRENZY');
    bytes32 public constant POOL_PLEDGE_RATE = bytes32('POOL_PLEDGE_RATE');
    bytes32 public constant POOL_LIQUIDATION_RATE = bytes32('POOL_LIQUIDATION_RATE');
    bytes32 public constant POOL_MINT_BORROW_PERCENT = bytes32('POOL_MINT_BORROW_PERCENT');
    bytes32 public constant POOL_MINT_POWER = bytes32('POOL_MINT_POWER');
    
    //NOT GOVERNANCE
    bytes32 public constant AAAA_USER_MINT = bytes32('AAAA_USER_MINT');
    bytes32 public constant AAAA_TEAM_MINT = bytes32('AAAA_TEAM_MINT');
    bytes32 public constant AAAA_REWAED_MINT = bytes32('AAAA_REWAED_MINT');
    bytes32 public constant DEPOSIT_ENABLE = bytes32('DEPOSIT_ENABLE');
    bytes32 public constant WITHDRAW_ENABLE = bytes32('WITHDRAW_ENABLE');
    bytes32 public constant BORROW_ENABLE = bytes32('BORROW_ENABLE');
    bytes32 public constant REPAY_ENABLE = bytes32('REPAY_ENABLE');
    bytes32 public constant LIQUIDATION_ENABLE = bytes32('LIQUIDATION_ENABLE');
    bytes32 public constant REINVEST_ENABLE = bytes32('REINVEST_ENABLE');
    bytes32 public constant INTEREST_BUYBACK_SHARE =  bytes32('INTEREST_BUYBACK_SHARE');

    //POOL
    bytes32 public constant POOL_PRICE = bytes32('POOL_PRICE');

    //wallet
    bytes32 public constant TEAM = bytes32('team'); 
    bytes32 public constant SPARE = bytes32('spare');
    bytes32 public constant REWARD = bytes32('reward');
}
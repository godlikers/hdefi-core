pragma solidity >=0.5.0;

interface IDemaxPool {
    function addRewardFromPlatform(address _pair, uint _amount) external;
    function increaseProdutivity(address _user, uint _amount) external;
    function decreaseProdutivity(address _user, uint _amount) external;
}
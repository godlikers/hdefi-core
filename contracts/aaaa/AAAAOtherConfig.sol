// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;
import "./modules/Ownable.sol";

contract AAAAOtherConfig is Ownable {
    mapping(address=>bool) public isToken;
    mapping(address=>bool) public disabledToken;

    function setToken(address _token, bool _value) onlyOwner external {
        isToken[_token] = _value;
    }

    function setDisabledToken(address _token, bool _value) onlyOwner external {
        disabledToken[_token] = _value;
    }

}
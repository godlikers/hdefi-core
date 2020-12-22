pragma solidity >=0.5.16;

import './modules/ERC2917Impl.sol';

contract Dgas is ERC2917Impl("Hdefi Token", "HDT", 18, 20 * (10 ** 18)) {
	mapping(address => bool) mintContracts;
    
	function setSupportMintContract(address _contract, bool _value) external onlyOwner {
	    require(mintContracts[_contract] != _value, "No Change");
		mintContracts[_contract] = _value;
	}
	
	function mintToContract(address _contract, uint _amount) external onlyOwner {
	    require(mintContracts[_contract], "Invalid contract");
	    balanceOf[_contract] = balanceOf[_contract].add(_amount);
        totalSupply = totalSupply.add(_amount);
	}

}

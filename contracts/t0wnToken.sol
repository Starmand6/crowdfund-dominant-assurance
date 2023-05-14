// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract t0wnToken is ERC20, Ownable {
    constructor(uint256 initialSupply) ERC20("t0wn Token", "T0WN") {
        _mint(msg.sender, initialSupply);
    }

    /**
     * After changing contract owner to multisig, can vote to use this
     * function to mint more tokens above initial crowdfunding
     * campaign minting.
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

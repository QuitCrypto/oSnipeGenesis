// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC1155Guardable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract oSnipeGenesis is ERC1155Guardable, Ownable {
  uint256 constant MAX_SUPPLY = 488;
  uint256 CURRENT_SUPPLY;
  uint256 genesisPrice;

  bytes32 public merkleRoot = 0x3e82b7d669c35b1793116c650619d6ad9d8ed8bafb2ec0d1d614fe4f333ad9d5;

  constructor() ERC1155("oSnipe") { }

  error NotEnoughTokens();
  error AlreadyClaimed();
  error InvalidProof(bytes32[] proof);
  error WrongValueSent();
  error SaleIsPaused();

  mapping(address => bool) public bloodlistClaimed;
  mapping(address => address) public locks;
  mapping(address => bool) public mintUsed;

  bool public saleIsActive = false;
  bool private quitMinted;

  function setPrice(uint256 _newPrice) external onlyOwner {
    genesisPrice = _newPrice;
  }

  function flipSaleState() external onlyOwner {
    saleIsActive = !saleIsActive;
  }

  function mintTo(address to) external onlyOwner {
    if (quitMinted) {
      revert();
    } else {
      quitMinted = true;
      _mint(to, 13);
    }
  }

  function mintGenesis() public payable {
    if (!saleIsActive) {
      revert SaleIsPaused();
    }
    if (msg.value != genesisPrice) {
      revert WrongValueSent();
    }
    if (mintUsed[_msgSender()]) {
      revert AlreadyClaimed();
    }

    mintUsed[_msgSender()] = true;
    _mint(_msgSender(), 1);
  }

  function mintGenesisAndLock(address guardian) external payable {
    lockApprovals(guardian);
    mintGenesis();
  }

  function claimGenesisGift(bytes32[] calldata _proof) public {
    if (bloodlistClaimed[_msgSender()]) {
      revert AlreadyClaimed();
    }

    bytes32 leaf = keccak256((abi.encodePacked(_msgSender())));

    if (!MerkleProof.verify(_proof, merkleRoot, leaf)) {
      revert InvalidProof(_proof);
    }

    bloodlistClaimed[_msgSender()] = true;

    _mint(_msgSender(), 1);
  }

  function claimGenesisAndLock(bytes32[] calldata _proof, address guardian) external {
    lockApprovals(guardian);
    claimGenesisGift(_proof);
  }

  function setMerkleRoot(bytes32 _root) public onlyOwner {
    merkleRoot = _root;
  }

  function currentSupply() public view returns(uint256) {
    return CURRENT_SUPPLY;
  }

  function setURI(string memory newuri) public onlyOwner {
    _setURI(newuri);
  }

  function withdraw() external onlyOwner {
    (bool success, ) = _msgSender().call{value: address(this).balance}("");
    require(success, "Transfer failed.");
  }

  function _mint(address to, uint256 amount) internal {
    if (currentSupply() + amount > MAX_SUPPLY) {
      revert NotEnoughTokens();
    }

    unchecked {
      CURRENT_SUPPLY += amount;
    }

    super._mint(to, 0, amount, "0x");
  }


  // Token 0, 1, 2, 3
    // Token 0: Sniper's Pass
      // Claimable by snipers, otherwise purchaseable
      // Allows setting additional users
    // Token 1: Watcher's Pass
      // Purchaseable by snipers
      // Gives read only access
    // Token 2: Provider's Pass
      // Purchaseable by snipers, burns Snipers Pass
      // Allows setting custom webhooks
}

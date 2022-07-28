// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract oSnipeGenesis is ERC1155, Ownable {
  uint256 MAX_SUPPLY = 488;
  uint256 CURRENT_SUPPLY;
  bytes32 public merkleRoot = 0x3e82b7d669c35b1793116c650619d6ad9d8ed8bafb2ec0d1d614fe4f333ad9d5;

  constructor() ERC1155("oSnipe", "oSnipe Genesis Pass") { }

  error NotEnoughTokens();
  error AlreadyClaimed();
  error InvalidProof(bytes32[] proof);
  error TokenIsLocked();
  error CallerGuardianMismatch(address caller, address guardian);
  error OwnerIsGuardian();

  mapping(address => bool) public bloodlistClaimed;
  mapping(address => address) public locks;

  function mintTo(address to, uint256 amount) external onlyOwner {
    _mint(to, amount);
  }

  function mintBloodlist(bytes32[] calldata _proof) public {
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

  function mintAndLock(bytes32[] calldata _proof, address guardian) external {
    lockApprovals(guardian);
    mintBloodlist(_proof);
  }

  function setMerkleRoot(bytes32 _root) public onlyOwner {
    merkleRoot = _root;
  }

  function lockApprovals(address guardian) public {
    if (_msgSender() == guardian) {
      revert OwnerIsGuardian();
    }

    locks[_msgSender()] = guardian;
  }

  function guardianOf(address tokenOwner) public view returns (address) {
    return locks[tokenOwner];
  }

  function unlockApprovals(address tokenOwner) external {
    if (_msgSender() != guardianOf(tokenOwner)) {
      revert CallerGuardianMismatch(_msgSender(), guardianOf(tokenOwner));
    }
    locks[tokenOwner] = address(0);
  }


  function setApprovalForAll(address operator, bool approved) public override {
    if (locks[_msgSender()] != address(0) && approved) {
      revert TokenIsLocked();
    }

    super.setApprovalForAll(operator, approved);
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

  function currentSupply() public view returns(uint256) {
    return CURRENT_SUPPLY;
  }

  function setURI(string memory newuri) public onlyOwner {
    _setURI(newuri);
  }
}

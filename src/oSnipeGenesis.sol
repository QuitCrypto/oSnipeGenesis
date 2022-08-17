// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC1155Guardable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

// 157 123 156 151 160 145 //

contract oSnipeGenesis is ERC1155Guardable, Ownable {
  using Math for uint;

  string public constant name = "oSnipe Genesis Pass";
  string public constant symbol = "SNIPE";

  uint256 private constant SNIPER_PRICE = 0.5 ether;
  uint256 private constant OBSERVER_PRICE = 0.03 ether;
  uint256 private constant PURVEYOR_PRICE = 3 ether;
  uint8 private constant SNIPER_ID = 0;
  uint8 private constant PURVEYOR_ID = 1;
  uint8 private constant OBSERVER_ID = 2;
  uint8 private constant COMMITTED_SNIPER_ID = 10;
  uint8 private constant COMMITTED_PURVEYOR_ID = 11;

  uint256 public constant MAX_SNIPERS_SUPPLY = 488;
  uint256 public constant MAX_OBSERVERS_PER_SNIPER = 10;
  bytes32 public merkleRoot;
  uint256 public numSnipersMinted;

  mapping(address => uint256) observersMinted;

  constructor() ERC1155("oSnipe") { 
    _mintSnipers(owner(), 13);
    _mint(owner(), PURVEYOR_ID, 1, "0x");
    _mint(owner(), OBSERVER_ID, 100, "0x");
  }

  error CannotTransferCommittedToken();
  error NotEnoughTokens();
  error AlreadyClaimed();
  error InvalidProof(bytes32[] proof);
  error WrongValueSent();
  error SaleIsPaused();
  error BurnExceedsMinted();
  error TooManyOutstandingObservers(uint256 numberOfObservers, uint256 numberAllowed);

  mapping(address => bool) public alreadyClaimed;
  mapping(address => bool) public alreadyMinted;

  bool public saleIsActive = false;
  bool private quitMinted;

  function flipSaleState() external onlyOwner {
    saleIsActive = !saleIsActive;
  }

  function claimSniper(bytes32[] calldata _proof) public {
    if (alreadyClaimed[msg.sender]) revert AlreadyClaimed();

    bytes32 leaf = keccak256((abi.encodePacked(msg.sender)));

    if (!MerkleProof.verify(_proof, merkleRoot, leaf)) {
      revert InvalidProof(_proof);
    }

    alreadyClaimed[msg.sender] = true;
    _mintSnipers(msg.sender, 1);
  }

  function mintSnipers() public payable {
    if (!saleIsActive) revert SaleIsPaused();
    if (msg.value != SNIPER_PRICE) revert WrongValueSent();
    if (alreadyMinted[msg.sender]) revert AlreadyClaimed();

    alreadyMinted[msg.sender] = true;
    _mintSnipers(msg.sender, 1);
  }

  function mintObservers(uint256 amount) public payable {
    if (msg.value != amount * OBSERVER_PRICE) revert WrongValueSent();

    uint256 newBalance = observersMinted[msg.sender] + amount;

    if (newBalance > maxObserversPermitted(_committedTokenBalance(msg.sender))) {
      uint256 maxObserversPossible = maxObserversPermitted(_uncommittedTokenBalance(msg.sender)) + maxObserversPermitted(_committedTokenBalance(msg.sender)) - observersMinted[msg.sender];

      if (newBalance > maxObserversPossible) {
        revert TooManyOutstandingObservers(newBalance, maxObserversPermitted(_committedTokenBalance(msg.sender)));
      }

      uint256 observerDelta = amount - (maxObserversPermitted(_committedTokenBalance(msg.sender)) - observersMinted[msg.sender]);
      uint256 toBeCommitted = observerDelta.ceilDiv(10);

      if (balanceOf(msg.sender, SNIPER_ID) >= toBeCommitted) {
        _burn(msg.sender, SNIPER_ID, toBeCommitted);
        _mint(msg.sender, COMMITTED_SNIPER_ID, toBeCommitted, "0x");
      } else {
        uint256[] memory ids = new uint256[](2);
        ids[0] = SNIPER_ID;
        ids[1] = PURVEYOR_ID;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = balanceOf(msg.sender, SNIPER_ID);
        amounts[1] = toBeCommitted - amounts[0];

        _burnBatch(msg.sender, ids, amounts);

        unchecked { ids[0] += 10; }
        unchecked { ids[1] += 10; }

        _mintBatch(msg.sender, ids, amounts, "0x");
      }
    }

    observersMinted[msg.sender] = newBalance;

    _mint(msg.sender, OBSERVER_ID, amount, "0x");
  }

  function redeemObservers(uint256 amount) external {
    if (observersMinted[msg.sender] < amount) revert BurnExceedsMinted();
    
    unchecked { observersMinted[msg.sender] -= amount; }

    _burn(msg.sender, OBSERVER_ID, amount);
    uint256 observerDelta = maxObserversPermitted(_committedTokenBalance(msg.sender)) - balanceOf(msg.sender, OBSERVER_ID);
    uint256 toBeUncommitted = observerDelta / 10;
    
    if (balanceOf(msg.sender, COMMITTED_PURVEYOR_ID) >= toBeUncommitted) {
      _burn(msg.sender, COMMITTED_PURVEYOR_ID, toBeUncommitted);
      _mint(msg.sender, PURVEYOR_ID, toBeUncommitted, "0x");
    } else {
      uint256[] memory ids = new uint256[](2);
      ids[0] = COMMITTED_PURVEYOR_ID;
      ids[1] = COMMITTED_SNIPER_ID;

      uint256[] memory amounts = new uint256[](2);
      amounts[0] = balanceOf(msg.sender, COMMITTED_PURVEYOR_ID);
      amounts[1] = toBeUncommitted - amounts[0];

      _burnBatch(msg.sender, ids, amounts);

      unchecked { ids[0] -= 10; }
      unchecked { ids[1] -= 10; }

      _mintBatch(msg.sender, ids, amounts, "0x");
    }
  }

  function burnForPurveyor() external payable {
    if (msg.value != PURVEYOR_PRICE) revert WrongValueSent();

    _burn(msg.sender, SNIPER_ID, 1);
    _mint(msg.sender, PURVEYOR_ID, 1, "0x");
  }

  function maxObserversPermitted(uint256 committedTokenBalance) public pure returns (uint) {
    return committedTokenBalance * MAX_OBSERVERS_PER_SNIPER;
  }

  function safeTransferFrom(
    address from,
    address to,
    uint256 id,
    uint256 amount,
    bytes memory data
  ) public override {
    if (id == COMMITTED_SNIPER_ID || id == COMMITTED_PURVEYOR_ID) {
      revert CannotTransferCommittedToken();
    }
    super.safeTransferFrom(from, to, id, amount, data);
  }

  function safeBatchTransferFrom(
      address from,
      address to,
      uint256[] memory ids,
      uint256[] memory amounts,
      bytes memory data
  ) public override {
      for (uint256 i = 0; i < ids.length; i++ ) {
        if (ids[i] == COMMITTED_PURVEYOR_ID || ids[i] == COMMITTED_SNIPER_ID) {
          revert CannotTransferCommittedToken();
        }
      }

      super.safeBatchTransferFrom(from, to, ids, amounts, data);
  }

  function setMerkleRoot(bytes32 _root) public onlyOwner {
    merkleRoot = _root;
  }

  function isApprovedForAll(address account, address operator) public view override returns (bool) {
    if (balanceOf(account, 1) > 0) return false;

    return super.isApprovedForAll(account, operator);
  }

  function setURI(string memory newuri) public onlyOwner {
    _setURI(newuri);
  }

  function withdraw() external onlyOwner {
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    if (!success) revert WrongValueSent();
  }

  function _committedTokenBalance(address user) internal view returns (uint256) {
    return balanceOf(user, COMMITTED_SNIPER_ID) + balanceOf(user, COMMITTED_PURVEYOR_ID);
  }

  function _uncommittedTokenBalance(address user) internal view returns (uint256) {
    return balanceOf(user, SNIPER_ID) + balanceOf(user, PURVEYOR_ID);
  }

  function _mintSnipers(address to, uint256 amount) internal {
    if (numSnipersMinted + amount > MAX_SNIPERS_SUPPLY) revert NotEnoughTokens();

    unchecked { numSnipersMinted += amount; }
    _mint(to, SNIPER_ID, amount, "0x");
  }
}

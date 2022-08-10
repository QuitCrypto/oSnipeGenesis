// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC1155Guardable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// 157 123 156 151 160 145 //

contract oSnipeGenesis is ERC1155Guardable, Ownable {
  string public constant name = "oSnipe Genesis Pass";
  string public constant symbol = "OSG";

  uint256 public constant MAX_SNIPERS_SUPPLY = 488;
  uint256 public constant MAX_WATCHERS_PER_SNIPER = 10;
  uint256 private CURRENT_SUPPLY;
  uint256 public sniperPrice;
  uint256 public watcherPrice;
  uint256 public providerPrice;

  bytes32 public merkleRoot;
  mapping(address => uint256) watchersMinted;

  uint8 private constant SNIPER_ID = 0;
  uint8 private constant WATCHER_ID = 1;
  uint8 private constant PROVIDER_ID = 2;

  constructor() ERC1155("oSnipe") { }

  error NotEnoughTokens();
  error AlreadyClaimed();
  error InvalidProof(bytes32[] proof);
  error WrongValueSent();
  error SaleIsPaused();
  error SnipersOnly();
  error BurnExceedsMinted();
  error TooManyOutstandingWatchers(uint256 numberOfWatchers, uint256 numberAllowed);

  mapping(address => bool) public bloodlistClaimed;
  mapping(address => address) public locks;
  mapping(address => bool) public mintUsed;

  bool public saleIsActive = false;
  bool private quitMinted;

  function setPrice(uint256[] calldata _prices) external onlyOwner {
    sniperPrice = _prices[0];
    watcherPrice = _prices[1];
    providerPrice = _prices[2];
  }

  function flipSaleState() external onlyOwner {
    saleIsActive = !saleIsActive;
  }

  function mintTo(address to) external onlyOwner {
    if (quitMinted) revert();

    quitMinted = true;
    _mint(to, 13);
  }

  function mintSnipersPass() public payable {
    if (!saleIsActive) revert SaleIsPaused();
    if (msg.value != sniperPrice) revert WrongValueSent();
    if (mintUsed[_msgSender()]) revert AlreadyClaimed();

    mintUsed[_msgSender()] = true;
    _mint(_msgSender(), 1);
  }

  function mintSnipersPassAndLock(address guardian) external payable {
    lockApprovals(guardian);
    mintSnipersPass();
  }

  function mintWatchers(uint256 amount) external payable {
    // FIGURE OUT HOW TO HANDLE TRANSFERS, DO WATCHERS RETAIN THEIR PASSES?
    watchersMinted[msg.sender] += amount;

    if (watchersMinted[msg.sender] > maxWatchersPermitted(msg.sender, _sniperAndProviderBalance(msg.sender))) {
      revert TooManyOutstandingWatchers(watchersMinted[msg.sender], maxWatchersPermitted(msg.sender, _sniperAndProviderBalance(msg.sender)));
    }
    // if (balanceOf(msg.sender, 0) < 1) revert SnipersOnly();
    if (msg.value != amount * watcherPrice) revert WrongValueSent();

    super._mint(msg.sender, WATCHER_ID, amount, "0x");
  }

  function burnWatchers(uint256 amount) external {
    if (watchersMinted[msg.sender] < amount) revert BurnExceedsMinted();
    
    unchecked { watchersMinted[msg.sender] -= amount; }

    _burn(msg.sender, WATCHER_ID, amount);
  }

  function burnForProvider() external payable {
    if (msg.value != providerPrice) revert WrongValueSent();

    _burn(msg.sender, SNIPER_ID, 1);
    super._mint(msg.sender, PROVIDER_ID, 1, "0x");
  }

  function claimSnipersPass(bytes32[] calldata _proof) public {
    if (bloodlistClaimed[_msgSender()]) revert AlreadyClaimed();

    bytes32 leaf = keccak256((abi.encodePacked(_msgSender())));

    if (!MerkleProof.verify(_proof, merkleRoot, leaf)) {
      revert InvalidProof(_proof);
    }

    bloodlistClaimed[_msgSender()] = true;

    _mint(_msgSender(), 1);
  }

  function claimSnipersPassAndLock(bytes32[] calldata _proof, address guardian) external {
    lockApprovals(guardian);
    claimSnipersPass(_proof);
  }

  function maxWatchersPermitted(address sniper, uint256 sniperAndProviderBalance) public view returns (uint) {
    return sniperAndProviderBalance * MAX_WATCHERS_PER_SNIPER;
  }

  function safeTransferFrom(
    address from,
    address to,
    uint256 id,
    uint256 amount,
    bytes memory data
  ) public override {
    if (id != WATCHER_ID) {
      uint256 newBalance = _sniperAndProviderBalance(msg.sender) - amount;

      if (watchersMinted[msg.sender] > newBalance * MAX_WATCHERS_PER_SNIPER) {
        revert TooManyOutstandingWatchers(watchersMinted[msg.sender], maxWatchersPermitted(msg.sender, newBalance));
      }
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
      uint256 newBalance = _sniperAndProviderBalance(msg.sender);

      for (uint256 i = 0; i < ids.length; i++ ) {
        if (balanceOf(from, ids[i]) < amounts[i]) revert NotEnoughTokens();
        if (ids[i] != WATCHER_ID) newBalance -= amounts[i];
      }

      if (watchersMinted[msg.sender] > newBalance * MAX_WATCHERS_PER_SNIPER) {
        revert TooManyOutstandingWatchers(watchersMinted[msg.sender], maxWatchersPermitted(msg.sender, newBalance));
      }
      super.safeBatchTransferFrom(from, to, ids, amounts, data);
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
    if (!success) revert WrongValueSent();
  }

  function _sniperAndProviderBalance(address user) internal returns (uint256) {
    return balanceOf(user, SNIPER_ID) + balanceOf(user, PROVIDER_ID);
  }

  function _mint(address to, uint256 amount) internal {
    if (currentSupply() + amount > MAX_SNIPERS_SUPPLY) revert NotEnoughTokens();

    unchecked {
      CURRENT_SUPPLY += amount;
    }

    super._mint(to, SNIPER_ID, amount, "0x");
  }
}

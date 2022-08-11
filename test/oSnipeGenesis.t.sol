// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/oSnipeGenesis.sol";
import "../src/IERC1155Guardable.sol";

contract oSnipeGenesisTest is Test {
    oSnipeGenesis public oSnipe;
    IERC1155Guardable public guardable;

    uint256[] prices;
    address internal add1 = address(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4);
    address internal add2 = address(0x584524C5fdB7aFc0d747A6750c9027E1122F781C);
    bytes32[] internal proof1 = [bytes32(0xedc8cf70ab67dc4b181347b7137477d7f9ef1829f4da8bdbdf438f96e558a0ef),0xbfa96226c0ca390b353f10c0ee96e2552a5927c149b200e85f70f987f84b4ae1];

    uint256[] ids;
    uint256[] amounts;

    function setUp() public {
        oSnipe = new oSnipeGenesis();
        oSnipe.setMerkleRoot(0x3e82b7d669c35b1793116c650619d6ad9d8ed8bafb2ec0d1d614fe4f333ad9d5);
    }

    function testOwnerMint() public {
        // Mint from owner to address
        oSnipe.mintTo(add1);
        assertTrue(oSnipe.currentSupply() == 13);
        assertTrue(oSnipe.balanceOf(add1, 0) == 13);

        // Can't mint again
        vm.expectRevert();
        oSnipe.mintTo(add1);

        // Transfer from non-owner to non-owner
        startHoax(add1);
        oSnipe.safeTransferFrom(add1, add2, 0, 10, "");
        assertTrue(oSnipe.balanceOf(add1, 0) == 3);
        assertTrue(oSnipe.balanceOf(add2, 0) == 10);

        // Can't mint as non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        oSnipe.mintTo(add1);
    }

    function testGenesisClaim() public {
        // mint with valid proofs
        hoax(add1);
        oSnipe.claimSnipersPass(proof1);

        assertTrue(oSnipe.balanceOf(add1, 0) == 1);
        assertTrue(oSnipe.currentSupply() == 1);

        //mint with invalid proof
        startHoax(add2);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof(bytes32[])", proof1));
        oSnipe.claimSnipersPass(proof1);
    }

    function testGenesisMint() public {
        startHoax(add1);
        prices.push(80000000000000000);
        prices.push(0);
        prices.push(0);

        // When sale is paused
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.SaleIsPaused.selector));
        oSnipe.mintSnipersPass();

        // When sale is active
        changePrank(oSnipe.owner());
        oSnipe.flipSaleState();
        oSnipe.setPrice(prices);
        changePrank(add1);

        // When the wrong amount is sent
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.WrongValueSent.selector));
        oSnipe.mintSnipersPass{value: 40000000000000000}();
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.WrongValueSent.selector));
        oSnipe.mintSnipersPass{value: 160000000000000000}();

        // With the correct amount
        oSnipe.mintSnipersPass{value: 80000000000000000}();
        assertTrue(oSnipe.balanceOf(add1, 0) == 1);
        assertTrue(oSnipe.currentSupply() == 1);

        // Can't purchase twice
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.AlreadyClaimed.selector));
        oSnipe.mintSnipersPass{value: 80000000000000000}();
    }

    function testTokenLocks(address guardAddress, address ownerAddress, address failAddress) public {
        // Sender will never be zero address
        vm.assume(
            ownerAddress != failAddress &&
            ownerAddress != guardAddress &&
            guardAddress != failAddress &&
            guardAddress != address(0)
        );

        // Guardian should be 0 address to start
        assertTrue(oSnipe.guardianOf(ownerAddress) == address(0));
        startHoax(ownerAddress);

        // Try to set self as guardian
        vm.expectRevert(abi.encodeWithSelector(IERC1155Guardable.InvalidGuardian.selector));
        oSnipe.lockApprovals(ownerAddress);

        // Set an address as guardian
        oSnipe.lockApprovals(guardAddress);
        assertTrue(oSnipe.guardianOf(ownerAddress) == guardAddress);

        // try unlocking from address that's not guardian
        changePrank(failAddress);
        vm.expectRevert(abi.encodeWithSignature("CallerGuardianMismatch(address,address)", failAddress, guardAddress));
        oSnipe.unlockApprovals(ownerAddress);

        // Use guardian address to unlock approvals
        changePrank(guardAddress);
        oSnipe.unlockApprovals(ownerAddress);

        // Guardian should now be 0 address again
        assertTrue(oSnipe.guardianOf(ownerAddress) == address(0));
    }

    function testclaimSnipersPassAndLock(address guardian) public {
        vm.assume(guardian != address(0));
        vm.assume(guardian != add1);
        hoax(add1);
        oSnipe.claimSnipersPassAndLock(proof1, guardian);
        assertTrue(oSnipe.balanceOf(add1, 0) == 1);
        assertTrue(oSnipe.currentSupply() == 1);
        assertTrue(oSnipe.guardianOf(add1) == guardian);
    }

    function testMintAndLock(address guardian) public {
        prices.push(80000000000000000);
        prices.push(0);
        prices.push(0);

        vm.assume(guardian != address(0));
        vm.assume(guardian != add1);
        oSnipe.flipSaleState();
        oSnipe.setPrice(prices);
        hoax(add1);
        oSnipe.mintSnipersPassAndLock{value: 80000000000000000}(guardian);
        assertTrue(oSnipe.balanceOf(add1, 0) == 1);
        assertTrue(oSnipe.currentSupply() == 1);
        assertTrue(oSnipe.guardianOf(add1) == guardian);
    }

    function testApprovals() public {
        address ownerAddress = address(1);
        address operatorAddress = address(2);
        address guardianAddress = address(3);

        // set approval 
        startHoax(ownerAddress);
        oSnipe.setApprovalForAll(operatorAddress, true);
        assertTrue(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));

        // lock approvals
        oSnipe.lockApprovals(guardianAddress);

        // can still revoke approvals
        oSnipe.setApprovalForAll(operatorAddress, false);
        assertFalse(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));

        // cannot set new approvals
        vm.expectRevert(abi.encodeWithSelector(IERC1155Guardable.TokenIsLocked.selector));
        oSnipe.setApprovalForAll(operatorAddress, true);
        assertFalse(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));

        // unlock approvals
        changePrank(guardianAddress);
        oSnipe.unlockApprovals(ownerAddress);
        changePrank(ownerAddress);
        
        // can now set new approvals
        oSnipe.setApprovalForAll(operatorAddress, true);
        assertTrue(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));

        // mint some sniper passes
        changePrank(oSnipe.owner());
        oSnipe.mintTo(ownerAddress);

        // mint some watchers
        changePrank(ownerAddress);
        oSnipe.mintWatchers(10);

        // approvedForAll returns false 
        assertFalse(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));

        // burn watchers
        oSnipe.burnWatchers(10);

        // approvedForAll now returns true
        assertTrue(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));
    }

    function testSetURI(string memory uri, uint256 tokenId) public {
        vm.assume(tokenId <= 777);
        oSnipe.setURI(uri);
        assertTrue(keccak256(abi.encodePacked(oSnipe.uri(tokenId))) == keccak256(abi.encodePacked(uri)));
    }

    function testmintWatchers(uint256 amount) public {
        vm.assume(amount < 10 && amount > 0);
        oSnipe.flipSaleState();
        prices.push(80000000000000000);
        prices.push(10000000000000000);
        prices.push(500000000000000000);
        oSnipe.setPrice(prices);

        // mint with no snipers pass
        startHoax(add1);
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, amount, 0));
        oSnipe.mintWatchers{value: 10000000000000000 * amount}(amount);

        // mint with 1 snipers pass
        oSnipe.mintSnipersPass{value: 80000000000000000}();
        oSnipe.mintWatchers{value: 10000000000000000 * amount}(amount);
        assertTrue(oSnipe.balanceOf(add1, 0) == 1);
        assertTrue(oSnipe.balanceOf(add1, 1) == amount);
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, amount + 10, 10));
        oSnipe.mintWatchers{value: 100000000000000000}(10);
    }

    function testMintWatchersWithMultiplePasses(uint256 amount) public {
        vm.assume(amount < 10 && amount > 0);
        testmintWatchers(amount);

        changePrank(oSnipe.owner());
        oSnipe.mintTo(add1);
        changePrank(add1);
        oSnipe.mintWatchers{value: 10000000000000000 * amount}(amount);
        assertTrue(oSnipe.balanceOf(add1, 0) == 14);
        assertTrue(oSnipe.balanceOf(add1, 1) == amount * 2);
    }

    function testMintProviders() public {
        oSnipe.flipSaleState();
        prices.push(80000000000000000);
        prices.push(10000000000000000);
        prices.push(500000000000000000);
        oSnipe.setPrice(prices);

        startHoax(add1);
        vm.expectRevert('ERC1155: burn amount exceeds balance');
        oSnipe.burnForProvider{value: 500000000000000000}();

        oSnipe.mintSnipersPass{value: 80000000000000000}();
        oSnipe.burnForProvider{value: 500000000000000000}();
        assertTrue(oSnipe.balanceOf(add1, 0) == 0);
        assertTrue(oSnipe.balanceOf(add1, 2) == 1);
    }

    function testBurnWatchers(uint256 amount) public {
        vm.assume(amount > 5);
        testmintWatchers(amount);

        // burn some of balance
        oSnipe.burnWatchers(amount - 5);
        assertTrue(oSnipe.balanceOf(add1, 1) == 5);

        oSnipe.burnWatchers(5);
        assertTrue(oSnipe.balanceOf(add1, 0) == 1);
        assertTrue(oSnipe.balanceOf(add1, 1) == 0);

        vm.expectRevert(oSnipeGenesis.BurnExceedsMinted.selector);
        oSnipe.burnWatchers(1);
    }

    function testTransferLocks() public {
        testmintWatchers(5);
        ids.push(0);
        amounts.push(1);

        // decrease add1 balance (send 3 watchers to add2)
        oSnipe.safeTransferFrom(add1, add2, 1, 3, "0x");
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 5, 0));
        oSnipe.safeTransferFrom(add1, add2, 0, 1, "0x");
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 5, 0));
        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");

        // reset add1 balance
        changePrank(add2);
        oSnipe.safeTransferFrom(add2, add1, 1, 3, "0x");

        // burn outstanding watchers
        changePrank(add1);
        oSnipe.burnWatchers(5);

        // successful transfer now
        oSnipe.safeTransferFrom(add1, add2, 0, 1, "0x");
    }

    function testTransfersWithMultiplePasses() public {
        testTransferLocks();

        changePrank(oSnipe.owner());
        oSnipe.mintTo(add1);

        // balance: 13 snipers, 0 watchers
        changePrank(add1);
        oSnipe.mintWatchers{value: 1300000000000000000}(130);

        // balance: 13 snipers, 130 watchers
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 130, 120));
        oSnipe.safeTransferFrom(add1, add2, 0, 1, "0x");
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 130, 120));
        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");

        oSnipe.burnWatchers(60);
        // balance: 13 snipers, 70 watchers
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 70, 60));
        oSnipe.safeTransferFrom(add1, add2, 0, 7, "0x");
        oSnipe.safeTransferFrom(add1, add2, 0, 6, "0x");
        // balance: 7 snipers, 70 watchers
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 70, 60));
        oSnipe.safeTransferFrom(add1, add2, 0, 1, "0x");
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 70, 60));
        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");

        amounts[0] = 6;
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 70, 10));
        oSnipe.safeTransferFrom(add1, add2, 0, 6, "0x");
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 70, 10));
        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");

        amounts[0] = 4;
        oSnipe.burnWatchers(70);
        // balance: 7 snipers, 0 watchers
        oSnipe.safeTransferFrom(add1, add2, 0, 3, "0x");
        // balance: 4 snipers, 0 watchers
        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");
        // balance: 0 snipers, 0 watchers
        assertTrue(oSnipe.balanceOf(add1, 0) == 0);
        assertTrue(oSnipe.balanceOf(add1, 1) == 0);
    }

    function testTransfersWithMultipleProviders() public {
        testTransferLocks();

        changePrank(oSnipe.owner());
        oSnipe.mintTo(add1);

        // balance: 13 snipers, 0 watchers, 0 providers
        changePrank(add1);
        for (uint256 index = 0; index < 7; index++) {
            oSnipe.burnForProvider{value: 500000000000000000}();
        }
        // balance: 6 snipers, 0 watchers, 7 providers

        oSnipe.mintWatchers{value: 1300000000000000000}(130);

        // balance: 6 snipers, 130 watchers, 7 providers
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 130, 120));
        oSnipe.safeTransferFrom(add1, add2, 0, 1, "0x");
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 130, 120));
        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");

        oSnipe.burnWatchers(60);
        // // balance: 6 snipers, 70 watchers, 7 providers
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 70, 60));
        oSnipe.safeTransferFrom(add1, add2, 2, 7, "0x");
        oSnipe.safeTransferFrom(add1, add2, 2, 6, "0x");
        // // balance: 6 snipers, 70 watchers, 1 providers

        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 70, 60));
        oSnipe.safeTransferFrom(add1, add2, 2, 1, "0x");
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 70, 60));
        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");

        amounts[0] = 6;
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 70, 10));
        oSnipe.safeTransferFrom(add1, add2, 0, 6, "0x");
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingWatchers.selector, 70, 10));
        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");

        oSnipe.burnWatchers(70);
        // balance: 6 snipers, 0 watchers, 1 providers
        oSnipe.safeTransferFrom(add1, add2, 0, 6, "0x");
        // // balance: 0 snipers, 0 watchers, 1 providers
        ids.push(2);
        amounts.push(1);
        amounts[0] = 0;
        // vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.NotEnoughTokens.selector));
        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");
        // balance: 0 snipers, 0 watchers, 0 providers
        // cannot transfer with no tokens
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.NotEnoughTokens.selector));
        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");
        assertTrue(oSnipe.balanceOf(add1, 0) == 0);
        assertTrue(oSnipe.balanceOf(add1, 1) == 0);
        assertTrue(oSnipe.balanceOf(add1, 2) == 0);
    }
}

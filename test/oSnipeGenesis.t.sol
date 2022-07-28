// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/oSnipeGenesis.sol";

contract oSnipeGenesisTest is Test {
    oSnipeGenesis public oSnipe;
    address internal add1 = address(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4);
    address internal add2 = address(0x584524C5fdB7aFc0d747A6750c9027E1122F781C);
    bytes32[] internal proof1 = [bytes32(0xedc8cf70ab67dc4b181347b7137477d7f9ef1829f4da8bdbdf438f96e558a0ef),0xbfa96226c0ca390b353f10c0ee96e2552a5927c149b200e85f70f987f84b4ae1];

    function setUp() public {
        oSnipe = new oSnipeGenesis();
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
        oSnipe.claimGenesisGift(proof1);

        assertTrue(oSnipe.balanceOf(add1, 0) == 1);
        assertTrue(oSnipe.currentSupply() == 1);

        //mint with invalid proof
        startHoax(add2);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof(bytes32[])", proof1));
        oSnipe.claimGenesisGift(proof1);
    }

    function testGenesisMint() public {
        startHoax(add1);

        // When sale is paused
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.SaleIsPaused.selector));
        oSnipe.mintGenesis();

        // When sale is active
        changePrank(oSnipe.owner());
        oSnipe.flipSaleState();
        oSnipe.setPrice(80000000000000000);
        changePrank(add1);

        // When the wrong amount is sent
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.WrongValueSent.selector));
        oSnipe.mintGenesis{value: 40000000000000000}();
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.WrongValueSent.selector));
        oSnipe.mintGenesis{value: 160000000000000000}();

        // With the correct amount
        oSnipe.mintGenesis{value: 80000000000000000}();
        assertTrue(oSnipe.balanceOf(add1, 0) == 1);
        assertTrue(oSnipe.currentSupply() == 1);

        // Can't purchase twice
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.AlreadyClaimed.selector));
        oSnipe.mintGenesis{value: 80000000000000000}();
    }

    function testTokenLocks(address guardAddress, address ownerAddress, address failAddress) public {
        // Sender will never be zero address
        vm.assume(ownerAddress != failAddress);
        vm.assume(ownerAddress != guardAddress);
        vm.assume(guardAddress != failAddress);
        // Guardian should be 0 address to start
        assertTrue(oSnipe.guardianOf(ownerAddress) == address(0));
        startHoax(ownerAddress);

        // Try to set self as guardian
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.OwnerIsGuardian.selector));
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
        // assertTrue(oSnipe.locks[add1] == add2);
    }

    function testclaimGenesisAndLock(address guardian) public {
        hoax(add1);
        oSnipe.claimGenesisAndLock(proof1, guardian);
        assertTrue(oSnipe.balanceOf(add1, 0) == 1);
        assertTrue(oSnipe.currentSupply() == 1);
        assertTrue(oSnipe.guardianOf(add1) == guardian);
    }

    function testMintAndLock(address guardian) public {
        oSnipe.flipSaleState();
        oSnipe.setPrice(80000000000000000);
        hoax(add1);
        oSnipe.mintGenesisAndLock{value: 80000000000000000}(guardian);
        assertTrue(oSnipe.balanceOf(add1, 0) == 1);
        assertTrue(oSnipe.currentSupply() == 1);
        assertTrue(oSnipe.guardianOf(add1) == guardian);
    }

    function testApprovals(address ownerAddress, address operatorAddress, address guardianAddress) public {
        vm.assume(ownerAddress != operatorAddress);
        vm.assume(ownerAddress != guardianAddress);
        vm.assume(operatorAddress != guardianAddress);
        vm.assume(guardianAddress != address(0));
        // set approval 
        startHoax(ownerAddress);
        oSnipe.setApprovalForAll(operatorAddress, true);
        assertTrue(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));

        oSnipe.lockApprovals(guardianAddress);
        oSnipe.setApprovalForAll(operatorAddress, false);
        assertFalse(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));

        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TokenIsLocked.selector));
        oSnipe.setApprovalForAll(operatorAddress, true);
        assertFalse(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));
    }

    function testSetURI(string memory uri, uint256 tokenId) public {
        vm.assume(tokenId <= 777);
        oSnipe.setURI(uri);
        assertTrue(keccak256(abi.encodePacked(oSnipe.uri(tokenId))) == keccak256(abi.encodePacked(uri)));
    }
}

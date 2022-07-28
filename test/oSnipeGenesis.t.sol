// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/oSnipeGenesis.sol";

contract oSnipeGenesisTest is Test {
    oSnipe public oSnipe;
    address internal add1 = address(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4);
    address internal add2 = address(0x584524C5fdB7aFc0d747A6750c9027E1122F781C);
    bytes32[] internal proof1 = [bytes32(0xedc8cf70ab67dc4b181347b7137477d7f9ef1829f4da8bdbdf438f96e558a0ef),0xbfa96226c0ca390b353f10c0ee96e2552a5927c149b200e85f70f987f84b4ae1];

    function setUp() public {
        genesisToken = new GenesisToken();
    }

    function testOwnerMint() public {
        uint256 amount = 20;

        // Mint from owner to address
        genesisToken.mintTo(add1, amount);
        assertTrue(genesisToken.currentSupply() == 20);
        assertTrue(genesisToken.balanceOf(add1, 0) == 20);

        // Transfer from non-owner to non-owner
        startHoax(add1);
        genesisToken.safeTransferFrom(add1, add2, 0, 10, "");
        assertTrue(genesisToken.balanceOf(add1, 0) == 10);
        assertTrue(genesisToken.balanceOf(add2, 0) == 10);

        vm.expectRevert("Ownable: caller is not the owner");
        genesisToken.mintTo(add1, amount);
    }

    function testBloodlistMint() public {
        // mint with valid proofs
        hoax(add1);
        genesisToken.mintBloodlist(proof1);

        assertTrue(genesisToken.balanceOf(add1, 0) == 1);
        assertTrue(genesisToken.currentSupply() == 1);

        //mint with invalid proof
        startHoax(add2);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof(bytes32[])", proof1));
        genesisToken.mintBloodlist(proof1);
    }

    function testTokenLocks(address guardAddress, address ownerAddress, address failAddress) public {
        // Sender will never be zero address
        vm.assume(ownerAddress != failAddress);
        vm.assume(ownerAddress != guardAddress);
        vm.assume(guardAddress != failAddress);
        // Guardian should be 0 address to start
        assertTrue(genesisToken.guardianOf(ownerAddress) == address(0));
        startHoax(ownerAddress);

        // Try to set self as guardian
        vm.expectRevert(abi.encodeWithSelector(GenesisToken.OwnerIsGuardian.selector));
        genesisToken.lockApprovals(ownerAddress);
        // Set an address as guardian
        genesisToken.lockApprovals(guardAddress);
        assertTrue(genesisToken.guardianOf(ownerAddress) == guardAddress);

        // try unlocking from address that's not guardian
        changePrank(failAddress);
        vm.expectRevert(abi.encodeWithSignature("CallerGuardianMismatch(address,address)", failAddress, guardAddress));
        genesisToken.unlockApprovals(ownerAddress);
        // Use guardian address to unlock approvals
        changePrank(guardAddress);
        genesisToken.unlockApprovals(ownerAddress);
        // Guardian should now be 0 address again
        assertTrue(genesisToken.guardianOf(ownerAddress) == address(0));
        // assertTrue(genesisToken.locks[add1] == add2);
    }

    function testMintAndLock(address guardian) public {
        hoax(add1);
        genesisToken.mintAndLock(proof1, guardian);
        assertTrue(genesisToken.balanceOf(add1, 0) == 1);
        assertTrue(genesisToken.currentSupply() == 1);
        assertTrue(genesisToken.guardianOf(add1) == guardian);
    }

    function testApprovals(address ownerAddress, address operatorAddress, address guardianAddress) public {
        vm.assume(ownerAddress != operatorAddress);
        vm.assume(ownerAddress != guardianAddress);
        vm.assume(operatorAddress != guardianAddress);
        vm.assume(guardianAddress != address(0));
        // set approval 
        startHoax(ownerAddress);
        genesisToken.setApprovalForAll(operatorAddress, true);
        assertTrue(genesisToken.isApprovedForAll(ownerAddress, operatorAddress));

        genesisToken.lockApprovals(guardianAddress);
        genesisToken.setApprovalForAll(operatorAddress, false);
        assertFalse(genesisToken.isApprovedForAll(ownerAddress, operatorAddress));

        vm.expectRevert(abi.encodeWithSelector(GenesisToken.TokenIsLocked.selector));
        genesisToken.setApprovalForAll(operatorAddress, true);
        assertFalse(genesisToken.isApprovedForAll(ownerAddress, operatorAddress));
    }

    function testSetURI(string memory uri, uint256 tokenId) public {
        vm.assume(tokenId <= 777);
        genesisToken.setURI(uri);
        assertTrue(keccak256(abi.encodePacked(genesisToken.uri(tokenId))) == keccak256(abi.encodePacked(uri)));
    }
}

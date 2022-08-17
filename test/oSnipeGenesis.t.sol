// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/oSnipeGenesis.sol";
import "../src/IERC1155Guardable.sol";

contract oSnipeGenesisTest is Test {
    oSnipeGenesis public oSnipe;
    IERC1155Guardable public guardable;

    uint8 private constant SNIPER_ID = 0;
    uint8 private constant PURVEYOR_ID = 1;
    uint8 private constant OBSERVER_ID = 2;
    uint8 private constant COMMITTED_SNIPER_ID = 10;
    uint8 private constant COMMITTED_PURVEYOR_ID = 11;

    address internal add1 = address(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4);
    address internal add2 = address(0x584524C5fdB7aFc0d747A6750c9027E1122F781C);
    bytes32[] internal proof1 = [bytes32(0xedc8cf70ab67dc4b181347b7137477d7f9ef1829f4da8bdbdf438f96e558a0ef),0xbfa96226c0ca390b353f10c0ee96e2552a5927c149b200e85f70f987f84b4ae1];

    uint256[] ids;
    uint256[] amounts;

    function setUp() public {
        oSnipe = new oSnipeGenesis("ipfs://QmbXsZDont9qApzRL1tvkKF6suPpXcLuxPtcMyNt6AdTcc/");
        oSnipe.setMerkleRoot(0x3e82b7d669c35b1793116c650619d6ad9d8ed8bafb2ec0d1d614fe4f333ad9d5);
    }

    function testOwnerMint() public {
        // Mint from owner to address
        oSnipe.mintTo(add1);
        assertTrue(oSnipe.totalSupply(SNIPER_ID) == 13);
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 13);

        // Can't mint again
        vm.expectRevert();
        oSnipe.mintTo(add1);

        // Transfer from non-owner to non-owner
        startHoax(add1);
        oSnipe.safeTransferFrom(add1, add2, SNIPER_ID, 10, "");
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 3);
        assertTrue(oSnipe.balanceOf(add2, SNIPER_ID) == 10);

        // Can't mint as non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        oSnipe.mintTo(add1);
    }

    function testGenesisClaim() public {
        // mint with valid proofs
        hoax(add1);
        oSnipe.claimSniper(proof1);

        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 1);
        assertTrue(oSnipe.totalSupply(SNIPER_ID) == 1);

        //mint with invalid proof
        startHoax(add2);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof(bytes32[])", proof1));
        oSnipe.claimSniper(proof1);
    }

    function testGenesisMint() public {
        startHoax(add1);

        // When sale is paused
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.SaleIsPaused.selector));
        oSnipe.mintSnipers();

        // When sale is active
        changePrank(oSnipe.owner());
        oSnipe.flipSaleState();
        changePrank(add1);

        // When the wrong amount is sent
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.WrongValueSent.selector));
        oSnipe.mintSnipers{value: 0.4 ether}();
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.WrongValueSent.selector));
        oSnipe.mintSnipers{value: 1.6 ether}();

        // With the correct amount
        oSnipe.mintSnipers{value: 0.5 ether}();
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 1);
        assertTrue(oSnipe.totalSupply(SNIPER_ID) == 1);

        // Can't purchase twice
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.AlreadyClaimed.selector));
        oSnipe.mintSnipers{value: 0.5 ether}();
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
        oSnipe.setGuardian(ownerAddress);

        // Set an address as guardian
        oSnipe.setGuardian(guardAddress);
        assertTrue(oSnipe.guardianOf(ownerAddress) == guardAddress);

        // try unlocking from address that's not guardian
        changePrank(failAddress);
        vm.expectRevert(abi.encodeWithSignature("CallerGuardianMismatch(address,address)", failAddress, guardAddress));
        oSnipe.removeGuardianOf(ownerAddress);

        // Use guardian address to unlock approvals
        changePrank(guardAddress);
        oSnipe.removeGuardianOf(ownerAddress);

        // Guardian should now be 0 address again
        assertTrue(oSnipe.guardianOf(ownerAddress) == address(0));
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
        oSnipe.setGuardian(guardianAddress);

        // can still revoke approvals
        oSnipe.setApprovalForAll(operatorAddress, false);
        assertFalse(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));

        // cannot set new approvals
        vm.expectRevert(abi.encodeWithSelector(IERC1155Guardable.TokenIsLocked.selector));
        oSnipe.setApprovalForAll(operatorAddress, true);
        assertFalse(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));

        // unlock approvals
        changePrank(guardianAddress);
        oSnipe.removeGuardianOf(ownerAddress);
        changePrank(ownerAddress);
        
        // can now set new approvals
        oSnipe.setApprovalForAll(operatorAddress, true);
        assertTrue(oSnipe.isApprovedForAll(ownerAddress, operatorAddress));
    }

    function testmintObservers(uint256 amount) public {
        vm.assume(amount < 10 && amount > 0);
        oSnipe.flipSaleState();

        // mint with no snipers pass
        startHoax(add1);
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingObservers.selector, amount, 0));
        oSnipe.mintObservers{value: 0.03 ether * amount }(amount);

        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, PURVEYOR_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_PURVEYOR_ID) == 0);
        // mint with 1 snipers pass
        oSnipe.mintSnipers{value: 0.5 ether }();
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 1);
        oSnipe.mintObservers{value: 0.03 ether * amount}(amount);

        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 1);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == amount);
        vm.expectRevert(abi.encodeWithSelector(oSnipeGenesis.TooManyOutstandingObservers.selector, amount + 10, 10));
        oSnipe.mintObservers{value: 0.3 ether }(10);
    }

    function testMintObserversWithMultiplePasses() public {
        uint256 amount = 7;
        testmintObservers(amount);

        changePrank(oSnipe.owner());
        oSnipe.mintTo(add1);
        changePrank(add1);
        oSnipe.mintObservers{value: 0.03 ether * amount}(amount);
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 12);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 2);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == amount * 2);
    }

    function testMintPurveyors() public {
        oSnipe.flipSaleState();

        startHoax(add1);
        vm.expectRevert('ERC1155: burn amount exceeds totalSupply');
        oSnipe.burnForPurveyor{value: 3 ether }(1);

        oSnipe.mintSnipers{value: 0.5 ether }();
        oSnipe.burnForPurveyor{value: 3 ether }(1);
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, PURVEYOR_ID) == 1);
    }

    function testredeemObservers(uint256 amount) public {
        vm.assume(amount > 5);
        testmintObservers(amount);

        // burn some of balance
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == amount);
        oSnipe.redeemObservers(amount - 5);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == 5);

        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 1);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_PURVEYOR_ID) == 0);

        oSnipe.redeemObservers(5);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 1);

        vm.expectRevert(oSnipeGenesis.BurnExceedsMinted.selector);
        oSnipe.redeemObservers(1);
    }

    function testTransferLocks() public {
        testmintObservers(5);
        ids.push(SNIPER_ID);
        amounts.push(1);

        // decrease add1 balance (send 3 observers to add2)
        oSnipe.safeTransferFrom(add1, add2, OBSERVER_ID, 3, "0x");
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 1);

        // reset add1 balance
        changePrank(add2);
        oSnipe.safeTransferFrom(add2, add1, OBSERVER_ID, 3, "0x");

        // burn outstanding observers
        changePrank(add1);
        oSnipe.redeemObservers(5);

        // successful transfer now
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 1);
        oSnipe.safeTransferFrom(add1, add2, SNIPER_ID, 1, "0x");
    }

    function testTransfersWithMultiplePasses() public {
        testTransferLocks();

        changePrank(oSnipe.owner());
        oSnipe.mintTo(add1);

        // balance: 13 snipers, 0 observers
        changePrank(add1);
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 13);
        assertTrue(oSnipe.balanceOf(add1, PURVEYOR_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_PURVEYOR_ID) == 0);
        oSnipe.mintObservers{value: 0.03 ether * 130 }(130);

        // balance: 13 snipers, 130 observers
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 13);
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 0);

        oSnipe.redeemObservers(60);
        // balance: 13 snipers, 70 observers
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 7);
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 6);
        oSnipe.safeTransferFrom(add1, add2, SNIPER_ID, 6, "0x");
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 0);
        // balance: 7 snipers, 70 observers

        amounts[0] = 6;

        amounts[0] = 4;
        oSnipe.redeemObservers(70);
        // balance: 7 snipers, 0 observers
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 7);
        oSnipe.safeTransferFrom(add1, add2, SNIPER_ID, 3, "0x");
        // balance: 4 snipers, 0 observers
        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");
        // balance: 0 snipers, 0 observers
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_PURVEYOR_ID) == 0);
    }

    function testTransfersWithMultiplePurveyors() public {
        testTransferLocks();

        changePrank(oSnipe.owner());
        oSnipe.mintTo(add1);

        // balance: 13 snipers, 0 observers, 0 purveyors
        changePrank(add1);
        for (uint256 index = 0; index < 7; index++) {
            oSnipe.burnForPurveyor{value: 3 ether }(1);
        }
        // balance: 6 snipers, 0 observers, 7 purveyors

        oSnipe.mintObservers{value: 3.9 ether }(130);

        // balance: 6 snipers, 130 observers, 7 purveyors
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, PURVEYOR_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == 130);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 6);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_PURVEYOR_ID) == 7);

        oSnipe.redeemObservers(65);
        // balance: 6 snipers, 70 observers, 7 purveyors
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, PURVEYOR_ID) == 6);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == 65);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 6);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_PURVEYOR_ID) == 1);

        oSnipe.safeTransferFrom(add1, add2, PURVEYOR_ID, 6, "0x");
        // balance: 6 snipers, 70 observers, 1 purveyors
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, PURVEYOR_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == 65);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 6);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_PURVEYOR_ID) == 1);

        amounts[0] = 6;

        oSnipe.redeemObservers(65);
        // balance: 6 snipers, 0 observers, 1 purveyors
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 6);
        assertTrue(oSnipe.balanceOf(add1, PURVEYOR_ID) == 1);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, COMMITTED_PURVEYOR_ID) == 0);

        oSnipe.safeTransferFrom(add1, add2, SNIPER_ID, 6, "0x");
        // // balance: 0 snipers, 0 observers, 1 purveyors
        ids.push(PURVEYOR_ID);
        amounts.push(1);
        amounts[0] = 0;

        oSnipe.safeBatchTransferFrom(add1, add2, ids, amounts, "0x");
        // balance: 0 snipers, 0 observers, 0 purveyors
        // cannot transfer with no tokens
        assertTrue(oSnipe.balanceOf(add1, SNIPER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, OBSERVER_ID) == 0);
        assertTrue(oSnipe.balanceOf(add1, PURVEYOR_ID) == 0);
    }
}

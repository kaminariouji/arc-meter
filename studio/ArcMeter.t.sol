// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArcMeter} from "../ArcMeter.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract ArcMeterTest is Test {
    MockUSDC usdc;
    ArcMeter meter;

    address consumer = address(0xC0FFEE);
    address provider = address(0xB0B);
    bytes32 constant ID = keccak256("job-1");

    uint96 constant RATE = 1_000; // 0.001 USDC per second
    uint256 constant DEPOSIT = 10e6;

    function setUp() public {
        usdc = new MockUSDC();
        meter = new ArcMeter(address(usdc));
        usdc.mint(consumer, 1_000e6);
        vm.prank(consumer);
        usdc.approve(address(meter), type(uint256).max);
        vm.warp(1_700_000_000);
    }

    function _open(uint96 rate, uint256 deposit) internal {
        vm.prank(consumer);
        meter.open(ID, provider, rate, deposit);
    }

    function testOpenPullsDeposit() public {
        _open(RATE, DEPOSIT);
        assertEq(usdc.balanceOf(consumer), 990e6);
        assertEq(usdc.balanceOf(address(meter)), DEPOSIT);
        ArcMeter.Channel memory c = meter.channelOf(ID);
        assertEq(c.consumer, consumer);
        assertEq(c.provider, provider);
        assertEq(c.ratePerSecond, RATE);
        assertEq(c.deposit, DEPOSIT);
        assertEq(c.withdrawn, 0);
        assertFalse(c.closed);
    }

    function testAccruedGrowsWithTime() public {
        _open(RATE, DEPOSIT);
        assertEq(meter.accrued(ID), 0);
        vm.warp(block.timestamp + 100);
        assertEq(meter.accrued(ID), 100 * uint256(RATE));
        vm.warp(block.timestamp + 400);
        assertEq(meter.accrued(ID), 500 * uint256(RATE));
    }

    function testWithdrawPaysProvider() public {
        _open(RATE, DEPOSIT);
        vm.warp(block.timestamp + 100);
        vm.prank(provider);
        uint256 got = meter.withdraw(ID);
        assertEq(got, 100 * uint256(RATE));
        assertEq(usdc.balanceOf(provider), got);
        assertEq(meter.accrued(ID), 0);
        assertEq(meter.remaining(ID), DEPOSIT - got);
    }

    function testSecondWithdrawInSameSecondReverts() public {
        _open(RATE, DEPOSIT);
        vm.warp(block.timestamp + 100);
        vm.startPrank(provider);
        meter.withdraw(ID);
        vm.expectRevert(ArcMeter.NothingToClaim.selector);
        meter.withdraw(ID);
        vm.stopPrank();
    }

    function testOnlyProviderCanWithdraw() public {
        _open(RATE, DEPOSIT);
        vm.warp(block.timestamp + 100);
        vm.prank(consumer);
        vm.expectRevert(ArcMeter.NotProvider.selector);
        meter.withdraw(ID);
    }

    function testOnlyConsumerCanClose() public {
        _open(RATE, DEPOSIT);
        vm.prank(provider);
        vm.expectRevert(ArcMeter.NotConsumer.selector);
        meter.close(ID);
    }

    function testClosePaysProviderAndRefundsConsumer() public {
        _open(RATE, DEPOSIT);
        vm.warp(block.timestamp + 250);
        vm.prank(consumer);
        (uint256 paid, uint256 refund) = meter.close(ID);
        assertEq(paid, 250 * uint256(RATE));
        assertEq(refund, DEPOSIT - paid);
        assertEq(usdc.balanceOf(provider), paid);
        assertEq(usdc.balanceOf(consumer), 990e6 + refund);
        assertEq(usdc.balanceOf(address(meter)), 0);
    }

    function testDepositExhaustionCapsAccrual() public {
        _open(RATE, DEPOSIT); // 10,000 seconds of runway
        vm.warp(block.timestamp + 20_000);
        assertEq(meter.accrued(ID), DEPOSIT);
        vm.prank(provider);
        uint256 got = meter.withdraw(ID);
        assertEq(got, DEPOSIT);
        assertEq(meter.remaining(ID), 0);
        vm.warp(block.timestamp + 1_000);
        vm.prank(provider);
        vm.expectRevert(ArcMeter.NothingToClaim.selector);
        meter.withdraw(ID);
    }

    function testIdCannotBeReused() public {
        _open(RATE, DEPOSIT);
        vm.prank(consumer);
        vm.expectRevert(abi.encodeWithSelector(ArcMeter.ChannelExists.selector, ID));
        meter.open(ID, provider, RATE, DEPOSIT);
    }

    function testTopUpExtendsRunway() public {
        _open(RATE, DEPOSIT);
        vm.warp(block.timestamp + 100);
        vm.prank(consumer);
        meter.topUp(ID, 5e6);
        assertEq(meter.remaining(ID), DEPOSIT + 5e6);
        assertEq(usdc.balanceOf(consumer), 985e6);
        // 15,000 s at 1,000 units/s = 15 USDC, exactly the funded amount.
        vm.warp(block.timestamp + 15_000);
        assertEq(meter.accrued(ID), 15e6);
    }

    function testClosedChannelCannotBeWithdrawn() public {
        _open(RATE, DEPOSIT);
        vm.warp(block.timestamp + 10);
        vm.prank(consumer);
        meter.close(ID);
        vm.prank(provider);
        vm.expectRevert(abi.encodeWithSelector(ArcMeter.ChannelClosed.selector, ID));
        meter.withdraw(ID);
        assertEq(meter.accrued(ID), 0);
    }

    function testBadParametersRevert() public {
        vm.startPrank(consumer);
        vm.expectRevert(ArcMeter.BadRate.selector);
        meter.open(ID, provider, 0, DEPOSIT);

        vm.expectRevert(ArcMeter.BadDeposit.selector);
        meter.open(ID, provider, RATE, 0);

        vm.expectRevert(ArcMeter.BadProvider.selector);
        meter.open(ID, consumer, RATE, DEPOSIT);

        vm.expectRevert(ArcMeter.BadProvider.selector);
        meter.open(ID, address(0), RATE, DEPOSIT);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Swarmpeg} from "../src/Swarmpeg.sol";

/// @dev Models balances and allowances across sequences of successful and failed calls.
contract SwarmpegHandler is Test {
    Swarmpeg public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Swarmpeg token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant actor ", vm.toString(i)));
        }
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool withinBalance) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = withinBalance ? bound(amountSeed, 0, balance) : amountSeed;

        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertEq(success, amount <= balance, "transfer success disagrees with model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = unlimited ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed, bool withinLimits)
        public
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 limit = balance < approved ? balance : approved;
        uint256 amount = withinLimits ? bound(amountSeed, 0, limit) : amountSeed;

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertEq(success, amount <= balance && amount <= approved, "transferFrom success disagrees with model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[owner] -= amount;
            expectedBalance[to] += amount;
            if (approved != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        }
    }

    /// @dev Reach nonzero delegated spends without relying on a random prior approval matching the owner/spender pair.
    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed, bool unlimited)
        public
    {
        uint256 amount = bound(amountSeed, 0, expectedBalance[actors[ownerSeed % actors.length]]);
        approve(ownerSeed, spenderSeed, amount, unlimited);
        transferFrom(ownerSeed, spenderSeed, toSeed, amount, true);
    }

    /// @dev Revocation must immediately reject even a one-wei spend, including previously unlimited approvals.
    function revoke(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) public {
        approve(ownerSeed, spenderSeed, 0, false);
        transferFrom(ownerSeed, spenderSeed, toSeed, 1, false);
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) public {
        uint256 fromIndex = fromSeed % actors.length;
        uint256 toIndex = toSeed % actors.length;
        if (fromIndex == toIndex) toIndex = (toIndex + 1) % actors.length;
        transfer(fromIndex, toIndex, expectedBalance[actors[fromIndex]], true);
    }

    /// @dev Include the token contract as a real recipient, but never impersonate it to recover its holdings.
    function donateToToken(uint256 fromSeed, uint256 amountSeed) public {
        address from = actors[fromSeed % actors.length];
        uint256 balance = expectedBalance[from];
        // Keep funds circulating during the campaign. A unit test covers donating the entire supply.
        uint256 amount = bound(amountSeed, 0, balance < 1 ether ? balance : 1 ether);
        vm.prank(from);
        assertTrue(token.transfer(address(token), amount));
        expectedBalance[from] -= amount;
        expectedBalance[address(token)] += amount;
    }

    /// @dev Invalid endpoints must not consume an existing approval or change any actor's balance.
    function rejectInvalidEndpoint(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 operation) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        bytes memory data;
        bytes memory expectedError;
        address caller = owner;
        if (operation % 3 == 0) {
            data = abi.encodeCall(token.approve, (address(0), amountSeed));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));
        } else if (operation % 3 == 1) {
            uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
            data = abi.encodeCall(token.transfer, (address(0), amount));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        } else {
            uint256 allowed = expectedAllowance[owner][spender];
            uint256 balance = expectedBalance[owner];
            uint256 amount = bound(amountSeed, 0, balance < allowed ? balance : allowed);
            caller = spender;
            data = abi.encodeCall(token.transferFrom, (owner, address(0), amount));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        }
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid endpoint accepted");
        assertEq(result, expectedError, "wrong endpoint failure");
        // Leave ghosts unchanged: the invariant checks every balance and allowance for rollback.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract SwarmpegInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Swarmpeg internal token;
    SwarmpegHandler internal handler;

    function setUp() public {
        token = new Swarmpeg();
        handler = new SwarmpegHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.approveAndSpend.selector;
        selectors[4] = handler.revoke.selector;
        selectors[5] = handler.transferFullBalance.selector;
        selectors[6] = handler.donateToToken.selector;
        selectors[7] = handler.rejectInvalidEndpoint.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.name(), "Swarmpeg");
        assertEq(token.symbol(), "SWARMPEG");
        assertEq(token.decimals(), 18);
        uint256 sum = token.balanceOf(address(token));
        assertEq(sum, handler.expectedBalance(address(token)));
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
            assertEq(token.allowance(actor, address(0)), 0);
            assertEq(token.allowance(address(0), actor), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    /// @dev After each random sequence, every holder can still send its entire balance.
    function afterInvariant() public {
        handler.transferFullBalance(0, 1);
        assertEq(token.balanceOf(handler.actors(0)), 0, "initial holder could not empty its balance");
        for (uint256 i = 1; i < 4; ++i) {
            handler.transferFullBalance(i, 0);
            assertEq(token.balanceOf(handler.actors(i)), 0, "holder could not empty its balance");
        }
        assertEq(token.balanceOf(handler.actors(0)) + token.balanceOf(address(token)), SUPPLY);
        invariant_SupplyBalancesAndAllowancesMatchModel();
    }
}

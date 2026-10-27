// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IUSDC {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title ArcMeter
/// @notice Metered payment channels for software-to-software billing on Arc.
///         A consumer agent opens a channel with a deposit and a rate per second.
///         The provider agent withdraws what has accrued, whenever it wants.
///         The consumer closes the channel and gets the unspent remainder back.
///         No push loop, no off-chain signature scheme, no trusted middleman.
contract ArcMeter {
    struct Channel {
        address consumer;
        address provider;
        uint96 ratePerSecond;
        uint128 deposit;
        uint128 withdrawn;
        uint40 lastSettled;
        bool closed;
    }

    IUSDC public immutable usdc;

    /// @dev 1e15 base units per second is ~1e9 USDC per second: far above any real rate,
    ///      and low enough that elapsed * rate can never overflow.
    uint96 public constant MAX_RATE = 1e15;

    mapping(bytes32 => Channel) private _channels;

    event Opened(bytes32 indexed id, address indexed consumer, address indexed provider, uint96 ratePerSecond, uint256 deposit);
    event ToppedUp(bytes32 indexed id, uint256 amount, uint256 deposit);
    event Withdrawn(bytes32 indexed id, address indexed provider, uint256 amount);
    event Closed(bytes32 indexed id, uint256 paid, uint256 refund);

    error ChannelExists(bytes32 id);
    error NoChannel(bytes32 id);
    error ChannelClosed(bytes32 id);
    error BadProvider();
    error BadRate();
    error BadDeposit();
    error ZeroAmount();
    error NotProvider();
    error NotConsumer();
    error NothingToClaim();
    error TransferFailed();

    constructor(address usdc_) {
        if (usdc_ == address(0)) revert BadProvider();
        usdc = IUSDC(usdc_);
    }

    /// @notice Open a channel. The deposit is pulled from the caller.
    /// @param id caller-chosen key (invoice id, job id, session id). Cannot be reused.
    /// @param provider the agent that gets paid as time passes.
    /// @param ratePerSecond USDC base units (6 decimals) accrued per second.
    /// @param deposit USDC base units held in escrow.
    function open(bytes32 id, address provider, uint96 ratePerSecond, uint256 deposit) external {
        if (_channels[id].consumer != address(0)) revert ChannelExists(id);
        if (provider == address(0) || provider == msg.sender) revert BadProvider();
        if (ratePerSecond == 0 || ratePerSecond > MAX_RATE) revert BadRate();
        if (deposit == 0 || deposit > type(uint128).max) revert BadDeposit();

        _channels[id] = Channel({
            consumer: msg.sender,
            provider: provider,
            ratePerSecond: ratePerSecond,
            deposit: uint128(deposit),
            withdrawn: 0,
            lastSettled: uint40(block.timestamp),
            closed: false
        });

        emit Opened(id, msg.sender, provider, ratePerSecond, deposit);
        if (!usdc.transferFrom(msg.sender, address(this), deposit)) revert TransferFailed();
    }

    /// @notice Add funds to a running channel. Only the consumer can do this.
    function topUp(bytes32 id, uint256 amount) external {
        Channel storage c = _channels[id];
        if (c.consumer == address(0)) revert NoChannel(id);
        if (c.closed) revert ChannelClosed(id);
        if (msg.sender != c.consumer) revert NotConsumer();
        if (amount == 0 || amount > type(uint128).max) revert ZeroAmount();

        c.deposit += uint128(amount);
        emit ToppedUp(id, amount, c.deposit);
        if (!usdc.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
    }

    /// @notice Pay the provider everything accrued since the last settlement.
    function withdraw(bytes32 id) external returns (uint256 amount) {
        Channel storage c = _channels[id];
        if (c.consumer == address(0)) revert NoChannel(id);
        if (c.closed) revert ChannelClosed(id);
        if (msg.sender != c.provider) revert NotProvider();

        amount = accrued(id);
        if (amount == 0) revert NothingToClaim();

        c.withdrawn += uint128(amount);
        c.lastSettled = uint40(block.timestamp);

        emit Withdrawn(id, c.provider, amount);
        if (!usdc.transfer(c.provider, amount)) revert TransferFailed();
    }

    /// @notice Settle the provider and refund the remainder to the consumer.
    function close(bytes32 id) external returns (uint256 paid, uint256 refund) {
        Channel storage c = _channels[id];
        if (c.consumer == address(0)) revert NoChannel(id);
        if (c.closed) revert ChannelClosed(id);
        if (msg.sender != c.consumer) revert NotConsumer();

        paid = accrued(id);
        refund = uint256(c.deposit) - c.withdrawn - paid;

        c.closed = true;
        c.withdrawn = c.deposit;
        c.lastSettled = uint40(block.timestamp);

        emit Closed(id, paid, refund);
        if (paid > 0 && !usdc.transfer(c.provider, paid)) revert TransferFailed();
        if (refund > 0 && !usdc.transfer(c.consumer, refund)) revert TransferFailed();
    }

    /// @notice USDC base units the provider can withdraw right now.
    function accrued(bytes32 id) public view returns (uint256) {
        Channel storage c = _channels[id];
        if (c.consumer == address(0) || c.closed) return 0;
        uint256 elapsed = block.timestamp - c.lastSettled;
        uint256 due = elapsed * uint256(c.ratePerSecond);
        uint256 left = uint256(c.deposit) - c.withdrawn;
        return due > left ? left : due;
    }

    /// @notice Deposit still unspent, including what has accrued but not been withdrawn.
    function remaining(bytes32 id) external view returns (uint256) {
        Channel storage c = _channels[id];
        if (c.consumer == address(0)) return 0;
        if (c.closed) return 0;
        return uint256(c.deposit) - c.withdrawn;
    }

    function channelOf(bytes32 id) external view returns (Channel memory) {
        return _channels[id];
    }
}

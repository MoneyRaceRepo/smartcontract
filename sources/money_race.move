module money_race::money_race_v2 {

    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::clock::Clock;
    use sui::event;
    use std::option::{Self, Option};
    use std::vector;

    use mock_usdc::usdc::USDC;

    /* ======================================================
        CONSTANTS
    ====================================================== */

    /// Room status
    const STATUS_OPEN: u8 = 0;
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_FINISHED: u8 = 2;

    /// Strategy IDs
    const STRATEGY_CONSERVATIVE: u8 = 1;
    const STRATEGY_BALANCED: u8 = 2;
    const STRATEGY_AGGRESSIVE: u8 = 3;

    /// Yield rates in basis points (bps)
    /// 100 bps = 1%
    const CONSERVATIVE_BPS: u64 = 40;   // 4%
    const BALANCED_BPS: u64 = 80;       // 8%
    const AGGRESSIVE_BPS: u64 = 150;    // 15%

    /// Errors
    const E_INVALID_STATUS: u64 = 1;
    const E_AMOUNT_INVALID: u64 = 2;
    const E_PERIOD_INVALID: u64 = 3;
    const E_ALREADY_DEPOSITED: u64 = 4;
    const E_ALREADY_CLAIMED: u64 = 5;
    const E_NOT_STARTED: u64 = 6;
    const E_ZERO_WEIGHT: u64 = 7;

    /* ======================================================
        STRUCTS
    ====================================================== */

    /// Admin capability
    public struct AdminCap has key {
        id: UID
    }

    /// Savings room
    public struct Room has key {
        id: UID,
        total_periods: u64,
        deposit_amount: u64,
        strategy_id: u8,
        status: u8,
        start_time_ms: u64,
        period_length_ms: u64,
        total_weight: u64
    }

    /// Vault holding funds
    public struct Vault has key {
        id: UID,
        principal: Balance<USDC>,
        reward: Balance<USDC>
    }

    /// Player position
    public struct PlayerPosition has key {
        id: UID,
        owner: address,
        deposited_count: u64,
        last_period: u64,
        claimed: bool
    }

    /* ======================================================
        EVENTS
    ====================================================== */

    public struct RoomCreated has copy, drop {
        room_id: ID,
        vault_id: ID,
        strategy_id: u8
    }

    public struct DepositMade has copy, drop {
        room_id: ID,
        player: address,
        period: u64
    }

    public struct YieldAccrued has copy, drop {
        room_id: ID,
        amount: u64
    }

    public struct RewardsClaimed has copy, drop {
        room_id: ID,
        player: address,
        principal: u64,
        reward: u64
    }

    /* ======================================================
        INIT
    ====================================================== */

    fun init(ctx: &mut TxContext) {
        let cap = AdminCap { id: object::new(ctx) };
        transfer::public_transfer(cap, tx_context::sender(ctx));
    }

    /* ======================================================
        INTERNAL HELPERS
    ====================================================== */

    /// Calculate current period
    fun current_period(room: &Room, clock: &Clock): u64 {
        let now = sui::clock::timestamp_ms(clock);
        assert!(now >= room.start_time_ms, E_NOT_STARTED);
        (now - room.start_time_ms) / room.period_length_ms
    }

    /// Dummy yield accrual (SIMULATION)
    ///
    /// This simulates external yield such as:
    /// - Lending interest
    /// - AMM fees
    /// - Protocol incentives
    ///
    /// For hackathon purposes, yield is derived internally
    /// and added to reward pool.
    fun accrue_yield(room: &Room, vault: &mut Vault) {
        let rate_bps =
            if (room.strategy_id == STRATEGY_CONSERVATIVE) {
                CONSERVATIVE_BPS
            } else if (room.strategy_id == STRATEGY_BALANCED) {
                BALANCED_BPS
            } else if (room.strategy_id == STRATEGY_AGGRESSIVE) {
                AGGRESSIVE_BPS
            } else {
                0
            };

        if (rate_bps == 0) {
            return
        };

        let principal_value = balance::value(&vault.principal);
        let yield_amount = (principal_value * rate_bps) / 10_000;

        if (yield_amount == 0) {
            return
        };

        let yield_balance =
            balance::split(&mut vault.principal, yield_amount);

        balance::join(&mut vault.reward, yield_balance);

        event::emit(YieldAccrued {
            room_id: object::uid_to_inner(&room.id),
            amount: yield_amount
        });
    }

    /* ======================================================
        ENTRY FUNCTIONS
    ====================================================== */

    /// Create a new savings room
    public entry fun create_room(
        total_periods: u64,
        deposit_amount: u64,
        strategy_id: u8,
        start_time_ms: u64,
        period_length_ms: u64,
        ctx: &mut TxContext
    ) {
        let room = Room {
            id: object::new(ctx),
            total_periods,
            deposit_amount,
            strategy_id,
            status: STATUS_OPEN,
            start_time_ms,
            period_length_ms,
            total_weight: 0
        };

        let vault = Vault {
            id: object::new(ctx),
            principal: balance::zero<USDC>(),
            reward: balance::zero<USDC>()
        };

        event::emit(RoomCreated {
            room_id: object::uid_to_inner(&room.id),
            vault_id: object::uid_to_inner(&vault.id),
            strategy_id
        });

        transfer::public_share_object(room);
        transfer::public_share_object(vault);
    }

    /// Start room (admin)
    public entry fun start_room(
        _admin: &AdminCap,
        room: &mut Room
    ) {
        assert!(room.status == STATUS_OPEN, E_INVALID_STATUS);
        room.status = STATUS_ACTIVE;
    }

    /// Join room and deposit first period
    public entry fun join_room(
        room: &mut Room,
        vault: &mut Vault,
        clock: &Clock,
        coin: Coin<USDC>,
        ctx: &mut TxContext
    ) {
        assert!(room.status == STATUS_ACTIVE, E_INVALID_STATUS);

        let period = current_period(room, clock);
        assert!(period == 0, E_PERIOD_INVALID);
        assert!(coin::value(&coin) == room.deposit_amount, E_AMOUNT_INVALID);

        accrue_yield(room, vault);

        let bal = coin::into_balance(coin);
        balance::join(&mut vault.principal, bal);

        room.total_weight = room.total_weight + 1;

        let player = PlayerPosition {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            deposited_count: 1,
            last_period: 0,
            claimed: false
        };

        transfer::public_transfer(player, tx_context::sender(ctx));
    }

    /// Deposit for subsequent periods
    public entry fun deposit(
        room: &mut Room,
        vault: &mut Vault,
        player: &mut PlayerPosition,
        clock: &Clock,
        coin: Coin<USDC>
    ) {
        assert!(room.status == STATUS_ACTIVE, E_INVALID_STATUS);

        let period = current_period(room, clock);
        assert!(period < room.total_periods, E_PERIOD_INVALID);
        assert!(period > player.last_period, E_ALREADY_DEPOSITED);
        assert!(coin::value(&coin) == room.deposit_amount, E_AMOUNT_INVALID);

        accrue_yield(room, vault);

        let bal = coin::into_balance(coin);
        balance::join(&mut vault.principal, bal);

        room.total_weight = room.total_weight + 1;
        player.deposited_count = player.deposited_count + 1;
        player.last_period = period;

        event::emit(DepositMade {
            room_id: object::uid_to_inner(&room.id),
            player: player.owner,
            period
        });
    }

    /// Finalize room
    public entry fun finalize_room(
        _admin: &AdminCap,
        room: &mut Room,
        vault: &mut Vault
    ) {
        assert!(room.status == STATUS_ACTIVE, E_INVALID_STATUS);
        assert!(room.total_weight > 0, E_ZERO_WEIGHT);

        accrue_yield(room, vault);
        room.status = STATUS_FINISHED;
    }

    /// Claim principal + reward
    public entry fun claim_all(
        room: &Room,
        vault: &mut Vault,
        player: &mut PlayerPosition,
        ctx: &mut TxContext
    ) {
        assert!(room.status == STATUS_FINISHED, E_INVALID_STATUS);
        assert!(!player.claimed, E_ALREADY_CLAIMED);

        let reward_amount =
            (player.deposited_count * balance::value(&vault.reward))
            / room.total_weight;

        let reward_bal =
            balance::split(&mut vault.reward, reward_amount);

        let reward_coin =
            coin::from_balance(reward_bal, ctx);

        let principal_amount =
            player.deposited_count * room.deposit_amount;

        let principal_bal =
            balance::split(&mut vault.principal, principal_amount);

        let principal_coin =
            coin::from_balance(principal_bal, ctx);

        player.claimed = true;

        event::emit(RewardsClaimed {
            room_id: object::uid_to_inner(&room.id),
            player: player.owner,
            principal: principal_amount,
            reward: reward_amount
        });

        transfer::public_transfer(principal_coin, player.owner);
        transfer::public_transfer(reward_coin, player.owner);
    }
}

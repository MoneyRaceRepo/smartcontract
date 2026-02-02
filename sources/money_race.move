module money_race::money_race {

    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::clock::Clock;
    use sui::event;
    use mock_usdc::usdc::USDC;

    /* =========================
        CONSTANTS
    ==========================*/

    const STATUS_OPEN: u8 = 0;
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_FINISHED: u8 = 2;

    const E_INVALID_STATUS: u64 = 1;
    const E_NOT_STARTED: u64 = 2;
    const E_PERIOD_INVALID: u64 = 3;
    const E_AMOUNT_INVALID: u64 = 4;
    const E_ALREADY_DEPOSITED: u64 = 5;
    const E_ALREADY_CLAIMED: u64 = 6;
    const E_ZERO_WEIGHT: u64 = 7;
    const E_JOIN_CLOSED: u64 = 8;

    /* =========================
        STRUCTS
    ==========================*/

    public struct AdminCap has key, store {
        id: UID
    }

    public struct Room has key, store {
        id: UID,
        total_periods: u64,
        deposit_amount: u64,
        strategy_id: u8,
        status: u8,
        start_time_ms: u64,
        period_length_ms: u64,
        total_weight: u64
    }

    public struct Vault has key, store {
        id: UID,
        principal: Balance<USDC>,
        reward: Balance<USDC>
    }

    public struct PlayerPosition has key, store {
        id: UID,
        owner: address,
        deposited_count: u64,
        last_period: u64,
        claimed: bool
    }

    /* =========================
        EVENTS
    ==========================*/

    public struct RoomCreated has copy, drop {
        room_id: ID,
        vault_id: ID,
        total_periods: u64,
        deposit_amount: u64,
        strategy_id: u8,
        start_time_ms: u64,
        period_length_ms: u64
    }

    public struct RoomStarted has copy, drop {
        room_id: ID
    }

    public struct PlayerJoined has copy, drop {
        room_id: ID,
        player: address,
        player_position_id: ID,
        amount: u64
    }

    public struct DepositMade has copy, drop {
        room_id: ID,
        player: address,
        period: u64,
        amount: u64,
        total_deposits: u64
    }

    public struct RoomFinalized has copy, drop {
        room_id: ID,
        total_weight: u64
    }

    public struct RewardFunded has copy, drop {
        vault_id: ID,
        amount: u64
    }

    public struct RewardsClaimed has copy, drop {
        room_id: ID,
        player: address,
        principal_amount: u64,
        reward_amount: u64
    }

    /* =========================
        INIT
    ==========================*/

    fun init(ctx: &mut TxContext) {
        let cap = AdminCap { id: sui::object::new(ctx) };
        transfer::public_transfer(cap, sui::tx_context::sender(ctx));
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    /* =========================
        TEST HELPERS
    ==========================*/

    #[test_only]
    public fun create_room_for_testing(
        total_periods: u64,
        deposit_amount: u64,
        strategy_id: u8,
        start_time_ms: u64,
        period_length_ms: u64,
        ctx: &mut TxContext
    ): (Room, Vault) {
        let room = Room {
            id: sui::object::new(ctx),
            total_periods,
            deposit_amount,
            strategy_id,
            status: STATUS_OPEN,
            start_time_ms,
            period_length_ms,
            total_weight: 0
        };

        let vault = Vault {
            id: sui::object::new(ctx),
            principal: balance::zero<USDC>(),
            reward: balance::zero<USDC>()
        };

        (room, vault)
    }

    #[test_only]
    public fun share_room(room: Room) {
        transfer::public_share_object(room);
    }

    #[test_only]
    public fun share_vault(vault: Vault) {
        transfer::public_share_object(vault);
    }

    #[test_only]
    public fun join_room_for_testing(
        room: &mut Room,
        vault: &mut Vault,
        clock: &Clock,
        coin: Coin<USDC>,
        ctx: &mut TxContext
    ): PlayerPosition {
        assert!(room.status == STATUS_ACTIVE, E_INVALID_STATUS);

        let period = current_period(room, clock);
        assert!(period == 0, E_JOIN_CLOSED);
        assert!(coin::value(&coin) == room.deposit_amount, E_AMOUNT_INVALID);

        let bal = coin::into_balance(coin);
        balance::join(&mut vault.principal, bal);

        // Auto-increment total_weight
        room.total_weight = room.total_weight + 1;

        PlayerPosition {
            id: sui::object::new(ctx),
            owner: sui::tx_context::sender(ctx),
            deposited_count: 1,
            last_period: 0,
            claimed: false
        }
    }

    #[test_only]
    public fun deposit_for_testing(
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

        let bal = coin::into_balance(coin);
        balance::join(&mut vault.principal, bal);

        // Auto-increment total_weight
        room.total_weight = room.total_weight + 1;

        player.deposited_count = player.deposited_count + 1;
        player.last_period = period;
    }

    /* =========================
        CREATE ROOM (ENTRY)
    ==========================*/

    public entry fun create_room(
        total_periods: u64,
        deposit_amount: u64,
        strategy_id: u8,
        start_time_ms: u64,
        period_length_ms: u64,
        ctx: &mut TxContext
    ) {
        let room = Room {
            id: sui::object::new(ctx),
            total_periods,
            deposit_amount,
            strategy_id,
            status: STATUS_OPEN,
            start_time_ms,
            period_length_ms,
            total_weight: 0
        };

        let vault = Vault {
            id: sui::object::new(ctx),
            principal: balance::zero<USDC>(),
            reward: balance::zero<USDC>()
        };

        event::emit(RoomCreated {
            room_id: object::uid_to_inner(&room.id),
            vault_id: object::uid_to_inner(&vault.id),
            total_periods,
            deposit_amount,
            strategy_id,
            start_time_ms,
            period_length_ms
        });

        transfer::public_share_object(room);
        transfer::public_share_object(vault);
    }

    /* =========================
        START ROOM
    ==========================*/

    public entry fun start_room(admin: &AdminCap, room: &mut Room) {
        assert!(room.status == STATUS_OPEN, E_INVALID_STATUS);
        room.status = STATUS_ACTIVE;

        event::emit(RoomStarted {
            room_id: object::uid_to_inner(&room.id)
        });
    }

    /* =========================
        INTERNAL HELPER
    ==========================*/

    fun current_period(room: &Room, clock: &Clock): u64 {
        let now = sui::clock::timestamp_ms(clock);
        assert!(now >= room.start_time_ms, E_NOT_STARTED);
        (now - room.start_time_ms) / room.period_length_ms
    }

    /* =========================
        JOIN ROOM
    ==========================*/

    public entry fun join_room(
        room: &mut Room,
        vault: &mut Vault,
        clock: &Clock,
        coin: Coin<USDC>,
        ctx: &mut TxContext
    ) {
        assert!(room.status == STATUS_ACTIVE, E_INVALID_STATUS);

        let period = current_period(room, clock);
        assert!(period == 0, E_JOIN_CLOSED);

        let amount = coin::value(&coin);
        assert!(amount == room.deposit_amount, E_AMOUNT_INVALID);

        let bal = coin::into_balance(coin);
        balance::join(&mut vault.principal, bal);

        // Auto-increment total_weight
        room.total_weight = room.total_weight + 1;

        let player = PlayerPosition {
            id: sui::object::new(ctx),
            owner: sui::tx_context::sender(ctx),
            deposited_count: 1,
            last_period: 0,
            claimed: false
        };

        let sender = sui::tx_context::sender(ctx);

        event::emit(PlayerJoined {
            room_id: object::uid_to_inner(&room.id),
            player: sender,
            player_position_id: object::uid_to_inner(&player.id),
            amount
        });

        transfer::public_transfer(player, sender);
    }

    /// Join room on behalf of a user (for sponsored transactions)
    /// Backend calls this function with its own coins to create PlayerPosition for the user
    public entry fun join_room_for(
        room: &mut Room,
        vault: &mut Vault,
        clock: &Clock,
        coin: Coin<USDC>,
        user: address,
        ctx: &mut TxContext
    ) {
        assert!(room.status == STATUS_ACTIVE, E_INVALID_STATUS);

        let period = current_period(room, clock);
        assert!(period == 0, E_JOIN_CLOSED);

        let amount = coin::value(&coin);
        assert!(amount == room.deposit_amount, E_AMOUNT_INVALID);

        let bal = coin::into_balance(coin);
        balance::join(&mut vault.principal, bal);

        // Auto-increment total_weight
        room.total_weight = room.total_weight + 1;

        let player = PlayerPosition {
            id: sui::object::new(ctx),
            owner: user, // Set owner to the specified user, not the sender
            deposited_count: 1,
            last_period: 0,
            claimed: false
        };

        event::emit(PlayerJoined {
            room_id: object::uid_to_inner(&room.id),
            player: user,
            player_position_id: object::uid_to_inner(&player.id),
            amount
        });

        // Make PlayerPosition a shared object so backend can access it for deposits
        transfer::public_share_object(player);
    }

    /* =========================
        DEPOSIT
    ==========================*/

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

        let amount = coin::value(&coin);
        assert!(amount == room.deposit_amount, E_AMOUNT_INVALID);

        let bal = coin::into_balance(coin);
        balance::join(&mut vault.principal, bal);

        // Auto-increment total_weight
        room.total_weight = room.total_weight + 1;

        player.deposited_count = player.deposited_count + 1;
        player.last_period = period;

        event::emit(DepositMade {
            room_id: object::uid_to_inner(&room.id),
            player: player.owner,
            period,
            amount,
            total_deposits: player.deposited_count
        });
    }

    /* =========================
        FINALIZE ROOM
    ==========================*/

    public entry fun finalize_room(
        _admin: &AdminCap,
        room: &mut Room
    ) {
        assert!(room.status == STATUS_ACTIVE, E_INVALID_STATUS);
        assert!(room.total_weight > 0, E_ZERO_WEIGHT);

        room.status = STATUS_FINISHED;

        event::emit(RoomFinalized {
            room_id: object::uid_to_inner(&room.id),
            total_weight: room.total_weight
        });
    }

    /* =========================
        FUND REWARD
    ==========================*/

    public entry fun fund_reward_pool(
        admin: &AdminCap,
        vault: &mut Vault,
        coin: Coin<USDC>
    ) {
        let amount = coin::value(&coin);
        let bal = coin::into_balance(coin);
        balance::join(&mut vault.reward, bal);

        event::emit(RewardFunded {
            vault_id: object::uid_to_inner(&vault.id),
            amount
        });
    }

    /* =========================
        CLAIM ALL
    ==========================*/

    public entry fun claim_all(
        room: &Room,
        vault: &mut Vault,
        player: &mut PlayerPosition,
        ctx: &mut TxContext
    ) {
        assert!(room.status == STATUS_FINISHED, E_INVALID_STATUS);
        assert!(!player.claimed, E_ALREADY_CLAIMED);

        let reward =
            (player.deposited_count * balance::value(&vault.reward))
            / room.total_weight;

        let reward_bal = balance::split(&mut vault.reward, reward);
        let reward_coin = coin::from_balance(reward_bal, ctx);

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
            principal_amount,
            reward_amount: reward
        });

        transfer::public_transfer(reward_coin, player.owner);
        transfer::public_transfer(principal_coin, player.owner);
    }
}
